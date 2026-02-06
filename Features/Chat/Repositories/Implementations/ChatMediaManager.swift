//
//  ChatMediaManager.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation
import UIKit
import Kingfisher
import AVFoundation
import AVKit

final class ChatMediaManager: ChatMediaManagerProtocol {
    private let storageManager: FirebaseStorageManager
    private let cacheManager: KingFisherCacheManager
    private let storageURLCache: OPStorageURLCache
    
    // 이미지/비디오 썸네일 준비 상태 추적
    private var preparedImageThumbMessageIDs: Set<String> = []
    private var preparedVideoThumbMessageIDs: Set<String> = []
    
    // 프로토콜 요구사항
    var messageImages: [String: [UIImage]] = [:]
    
    init(
        storageManager: FirebaseStorageManager = .shared,
        cacheManager: KingFisherCacheManager = .shared,
        storageURLCache: OPStorageURLCache? = nil
    ) {
        self.storageManager = storageManager
        self.cacheManager = cacheManager
        self.storageURLCache = storageURLCache ?? OPStorageURLCache()
    }
    
    func cacheImagesIfNeeded(for message: ChatMessage) async -> [UIImage] {
        guard !message.attachments.isEmpty else { return [] }
        
        let alreadyPrepared = await MainActor.run { preparedImageThumbMessageIDs.contains(message.ID) }
        if alreadyPrepared { return [] }
        
        let imageAttachments = message.attachments
            .filter { $0.type == .image }
            .sorted { $0.index < $1.index }
        
        var images: [UIImage] = []
        
        for attachment in imageAttachments {
            let key = attachment.hash
            do {
                let cache = KingfisherManager.shared.cache
                cache.memoryStorage.config.expiration = .seconds(3600)
                cache.diskStorage.config.expiration = .days(3)
                
                if await cacheManager.isCached(key) {
                    if let img = await cacheManager.loadImage(named: key) {
                        images.append(img)
                    }
                } else {
                    let img = try await storageManager.fetchImageFromStorage(image: attachment.pathThumb, location: .roomImage)
                    cacheManager.storeImage(img, forKey: key)
                    images.append(img)
                }
            } catch {
                print("⚠️ 이미지 캐시 실패: \(error)")
            }
        }
        
        await MainActor.run {
            preparedImageThumbMessageIDs.insert(message.ID)
        }
        
        return images
    }
    
    func cacheVideoAssetsIfNeeded(for message: ChatMessage, in roomID: String) async {
        let videoAttachments = message.attachments
            .filter { $0.type == .video }
            .sorted { $0.index < $1.index }
        
        guard !videoAttachments.isEmpty else { return }
        
        let alreadyPrepared = await MainActor.run { preparedVideoThumbMessageIDs.contains(message.ID) }
        if alreadyPrepared { return }
        
        for attachment in videoAttachments {
            let thumbPath = attachment.pathThumb
            let key = attachment.hash.isEmpty ? thumbPath : attachment.hash
            
            if !thumbPath.isEmpty {
                do {
                    let cache = KingfisherManager.shared.cache
                    cache.memoryStorage.config.expiration = .seconds(3600)
                    cache.diskStorage.config.expiration = .days(3)
                    
                    if await cacheManager.isCached(key) {
                        // 이미 캐시됨
                    } else {
                        let isLocalFile = thumbPath.hasPrefix("/") || thumbPath.hasPrefix("file://")
                        if isLocalFile {
                            let fileURL = thumbPath.hasPrefix("file://") ? URL(string: thumbPath)! : URL(fileURLWithPath: thumbPath)
                            if let data = try? Data(contentsOf: fileURL),
                               let img = UIImage(data: data) {
                                cacheManager.storeImage(img, forKey: key)
                            }
                        } else {
                            let img = try await storageManager.fetchImageFromStorage(image: thumbPath, location: .roomImage)
                            cacheManager.storeImage(img, forKey: key)
                        }
                    }
                } catch {
                    print("⚠️ 비디오 썸네일 캐시 실패:", error)
                }
            }
            
            // 원본 비디오 downloadURL warm-up
            let path = attachment.pathOriginal
            if !path.isEmpty, !path.hasPrefix("/") {
                _ = try? await storageURLCache.url(for: path)
            }
        }
        
        await MainActor.run {
            preparedVideoThumbMessageIDs.insert(message.ID)
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
    
    func resolveURLs(for paths: [String], concurrent: Int) async -> [URL] {
        guard !paths.isEmpty else { return [] }
        var urls = Array<URL?>(repeating: nil, count: paths.count)
        var idx = 0
        
        while idx < paths.count {
            let end = min(idx + concurrent, paths.count)
            await withTaskGroup(of: (Int, URL?).self) { group in
                for i in idx..<end {
                    let p = paths[i]
                    group.addTask { [storageURLCache] in
                        do { return (i, try await storageURLCache.url(for: p)) }
                        catch { return (i, nil) }
                    }
                }
                for await (i, u) in group { urls[i] = u }
            }
            idx = end
        }
        
        return urls.compactMap { $0 }
    }
    
    func resolveURL(for path: String) async throws -> URL {
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

