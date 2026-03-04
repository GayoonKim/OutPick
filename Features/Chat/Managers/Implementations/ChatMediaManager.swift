//
//  ChatMediaManager.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation
import UIKit
import AVFoundation
import AVKit

final class ChatMediaManager: ChatMediaManaging {
    private let imageStorageManager: FirebaseImageStorageRepositoryProtocol
    private let storageURLCache: OPStorageURLCache
    private let imagePipeline: ImageCachePipeline
    private let imageThumbMaxBytes = 12 * 1024 * 1024
    
    // 비디오 썸네일/URL warm-up 상태 추적
    private var preparedVideoThumbMessageIDs: Set<String> = []
    
    init(
        imageStorageManager: FirebaseImageStorageRepositoryProtocol = FirebaseImageStorageRepository.shared,
        storageURLCache: OPStorageURLCache? = nil,
        imagePipeline: ImageCachePipeline? = nil
    ) {
        self.imageStorageManager = imageStorageManager
        self.storageURLCache = storageURLCache ?? OPStorageURLCache()
        self.imagePipeline = imagePipeline ?? ImageCachePipeline(
            fetcher: { [imageStorageManager] path, maxBytes in
                try await imageStorageManager.fetchImageDataFromStorage(
                    image: path,
                    location: .roomImage,
                    maxBytes: maxBytes
                )
            },
            disk: ImageCacheDiskStore(
                folderName: "ChatImageCache",
                maxSizeBytes: 350 * 1024 * 1024,
                trimTargetBytes: 280 * 1024 * 1024
            )
        )
    }
    
    func cacheImagesIfNeeded(for message: ChatMessage) async -> [UIImage] {
        guard !message.attachments.isEmpty else { return [] }

        // UI 썸네일은 이미지/비디오 모두 필요합니다.
        let thumbAttachments = message.attachments
            .filter { $0.type == .image || $0.type == .video }
            .sorted { $0.index < $1.index }
        
        var images: [UIImage] = []
        
        for attachment in thumbAttachments {
            let thumbPath = attachment.pathThumb
            guard !thumbPath.isEmpty else { continue }
            do {
                let img = try await loadImage(for: thumbPath, maxBytes: imageThumbMaxBytes)
                images.append(img)
            } catch {
                print("⚠️ 이미지 캐시 실패: \(error)")
            }
        }

        return images
    }
    
    func cacheVideoAssetsIfNeeded(for message: ChatMessage, in _: String) async {
        let videoAttachments = message.attachments
            .filter { $0.type == .video }
            .sorted { $0.index < $1.index }
        
        guard !videoAttachments.isEmpty else { return }
        
        let alreadyPrepared = await MainActor.run { preparedVideoThumbMessageIDs.contains(message.ID) }
        if alreadyPrepared { return }
        
        for attachment in videoAttachments {
            let thumbPath = attachment.pathThumb
            
            if !thumbPath.isEmpty {
                _ = try? await loadImage(for: thumbPath, maxBytes: imageThumbMaxBytes)
            }
            
            // 원본 비디오 downloadURL warm-up
            let path = attachment.pathOriginal
            if !path.isEmpty, isStoragePath(path) {
                _ = try? await storageURLCache.url(for: path)
            }
        }
        
        await MainActor.run {
            _ = preparedVideoThumbMessageIDs.insert(message.ID)
        }
    }
    
    func prefetchThumbnails(for messages: [ChatMessage], maxConcurrent: Int) async {
        let imageMessages = messages.filter { $0.attachments.contains { $0.type == .image } }
        
        var index = 0
        while index < imageMessages.count {
            let end = min(index + maxConcurrent, imageMessages.count)
            let slice = Array(imageMessages[index..<end])
            
            await withTaskGroup(of: Void.self) { group in
                for msg in slice {
                    group.addTask { [weak self] in
                        guard let self = self else { return }
                        _ = await self.cacheImagesIfNeeded(for: msg)
                    }
                }
                await group.waitForAll()
            }
            index = end
        }
    }
    
    func prefetchVideoAssets(for messages: [ChatMessage], maxConcurrent: Int, roomID: String) async {
        let videoMessages = messages.filter { $0.attachments.contains { $0.type == .video } }
        var index = 0
        
        while index < videoMessages.count {
            let end = min(index + maxConcurrent, videoMessages.count)
            let slice = Array(videoMessages[index..<end])
            
            await withTaskGroup(of: Void.self) { group in
                for msg in slice {
                    group.addTask { [weak self] in
                        guard let self = self else { return }
                        await self.cacheVideoAssetsIfNeeded(for: msg, in: roomID)
                    }
                }
                await group.waitForAll()
            }
            index = end
        }
    }

    func cachedImage(for path: String) async -> UIImage? {
        guard !path.isEmpty else { return nil }

        if let local = loadLocalImage(from: path) {
            return local
        }

        if isStoragePath(path) {
            return await imagePipeline.cachedImage(path: path)
        }

        return nil
    }

    func loadImage(for path: String, maxBytes: Int) async throws -> UIImage {
        if let local = loadLocalImage(from: path) {
            return local
        }

        if isStoragePath(path) {
            return try await imagePipeline.loadImage(path: path, maxBytes: maxBytes)
        }

        throw URLError(.badURL)
    }

    func prefetchImages(paths: [String], maxBytes: Int, maxConcurrent: Int) async {
        let normalized = Array(Set(paths.filter { isStoragePath($0) }))
        guard !normalized.isEmpty else { return }
        let items = normalized.map { (path: $0, maxBytes: maxBytes) }
        await imagePipeline.prefetch(items: items, concurrency: maxConcurrent)
    }
    
    func resolveURL(for path: String) async throws -> URL {
        if let direct = URL(string: path),
           let scheme = direct.scheme?.lowercased(),
           ["http", "https", "file"].contains(scheme) {
            return direct
        }
        return try await storageURLCache.url(for: path)
    }
    
    // MARK: - 비디오 관련 메서드 (기본 구현 - ChatViewController에서 오버라이드 가능)
    
    func uploadCompressedVideoAndBroadcast(roomID: String, compressedURL: URL, preset: DefaultMediaProcessingService.VideoUploadPreset, hud: CircularProgressHUD?) async {
        // 이 메서드는 ChatViewController의 특정 기능과 밀접하게 연관되어 있어
        // ChatViewController에서 직접 구현하는 것이 더 적합합니다.
        // 프로토콜 요구사항을 만족하기 위한 기본 구현입니다.
        fatalError("uploadCompressedVideoAndBroadcast는 ChatViewController에서 구현되어야 합니다.")
    }
    
    func makeVideoThumbnailData(url: URL, maxPixel: CGFloat) throws -> Data {
        let asset = AVAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        let cg = try gen.copyCGImage(at: .zero, actualTime: nil)
        let ui = UIImage(cgImage: cg)
        let scaled = ui.resizeMaxPixel(maxPixel)
        return scaled.jpegData(compressionQuality: 0.8) ?? Data()
    }
    
    func playVideoForStoragePath(_ storagePath: String, in viewController: UIViewController) async {
        guard !storagePath.isEmpty else { return }
        do {
            if let local = await OPVideoDiskCache.shared.exists(forKey: storagePath) {
                await MainActor.run {
                    let player = AVPlayer(url: local)
                    let playerVC = AVPlayerViewController()
                    playerVC.player = player
                    playerVC.modalPresentationStyle = .fullScreen
                    viewController.present(playerVC, animated: true)
                }
                return
            }
            let remote = try await storageURLCache.url(for: storagePath)
            await MainActor.run {
                let player = AVPlayer(url: remote)
                let playerVC = AVPlayerViewController()
                playerVC.player = player
                playerVC.modalPresentationStyle = .fullScreen
                viewController.present(playerVC, animated: true)
            }
            Task.detached { _ = try? await OPVideoDiskCache.shared.cache(from: remote, key: storagePath) }
        } catch {
            await MainActor.run {
                AlertManager.showAlertNoHandler(
                    title: "재생 실패",
                    message: "동영상을 불러오지 못했습니다.\n\(error.localizedDescription)",
                    viewController: viewController
                )
            }
        }
    }
    
    func resolveLocalFileURLForSaving(localURL: URL?, storagePath: String?, onProgress: @escaping (Double) -> Void) async throws -> URL {
        if let localURL, localURL.isFileURL { return localURL }
        
        if let storagePath,
           let cached = await OPVideoDiskCache.shared.exists(forKey: storagePath) {
            return cached
        }
        
        if let storagePath {
            let remote = try await storageURLCache.url(for: storagePath)
            return try await downloadToTemporaryFile(from: remote, onProgress: onProgress)
        }
        
        if let remote = localURL, (remote.scheme?.hasPrefix("http") == true) {
            return try await downloadToTemporaryFile(from: remote, onProgress: onProgress)
        }
        
        throw NSError(domain: "SaveVideo", code: -2,
                      userInfo: [NSLocalizedDescriptionKey: "저장할 파일 경로를 확인할 수 없습니다."])
    }
    
    private func downloadToTemporaryFile(from remote: URL, onProgress: @escaping (Double) -> Void) async throws -> URL {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("save_\(UUID().uuidString).mp4")
        let (data, _) = try await URLSession.shared.data(from: remote)
        try data.write(to: tmp, options: .atomic)
        return tmp
    }

    private func isStoragePath(_ path: String) -> Bool {
        !path.isEmpty && !path.isLocalFilePath
    }

    private func loadLocalImage(from path: String) -> UIImage? {
        guard let fileURL = path.localFileURL else { return nil }
        guard let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return nil
        }
        return image
    }
}

private extension String {
    var isLocalFilePath: Bool {
        hasPrefix("/") || hasPrefix("file://")
    }

    var localFileURL: URL? {
        if hasPrefix("file://") {
            return URL(string: self)
        }
        if hasPrefix("/") {
            return URL(fileURLWithPath: self)
        }
        return nil
    }
}

// MARK: - UIImage Extension for resizeMaxPixel
extension UIImage {
    /// Longer side will be resized to `maxPixel` while preserving aspect ratio.
    /// If the image is already within bounds or `maxPixel` <= 0, returns self.
    func resizeMaxPixel(_ maxPixel: CGFloat) -> UIImage {
        guard maxPixel > 0 else { return self }
        let w = size.width
        let h = size.height
        guard w > 0, h > 0 else { return self }
        let longSide = max(w, h)
        guard longSide > maxPixel else { return self }

        let scaleRatio = maxPixel / longSide
        var newW = floor(w * scaleRatio)
        var newH = floor(h * scaleRatio)
        // enforce even pixels (some encoders prefer multiples of 2)
        newW = max(2, floor(newW / 2) * 2)
        newH = max(2, floor(newH / 2) * 2)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1   // 1 point == 1 pixel in the output
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: newW, height: newH), format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(x: 0, y: 0, width: newW, height: newH))
        }
    }
}
