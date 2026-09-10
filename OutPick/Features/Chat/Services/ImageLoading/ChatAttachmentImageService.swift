//
//  ChatAttachmentImageService.swift
//  OutPick
//
//  Created by Codex on 6/23/26.
//

import Foundation
import ImageIO
import UIKit

struct ChatAttachmentImagePipelines {
    let remote: ImageCachePipeline
    let outgoingPreview: ImageCachePipeline
}

final class ChatAttachmentImageService: ChatAttachmentImageLoading {
    static let shared = ChatAttachmentImageService(
        imageStorageRepository: FirebaseRepositoryProvider.shared.imageStorageRepository
    )

    private static let sharedPipelines = makePipelines(
        imageStorageRepository: FirebaseRepositoryProvider.shared.imageStorageRepository
    )

    private let pipelines: ChatAttachmentImagePipelines
    private let imageStorageRepository: FirebaseImageStorageRepositoryProtocol
    private let imageDataCache = NSCache<NSString, NSData>()

    init(
        imageStorageRepository: FirebaseImageStorageRepositoryProtocol,
        pipelines: ChatAttachmentImagePipelines? = nil
    ) {
        self.imageStorageRepository = imageStorageRepository
        if let pipelines {
            self.pipelines = pipelines
        } else if imageStorageRepository is FirebaseImageStorageRepository {
            self.pipelines = Self.sharedPipelines
        } else {
            self.pipelines = Self.makePipelines(imageStorageRepository: imageStorageRepository)
        }
        imageDataCache.totalCostLimit = 45 * 1024 * 1024
    }

    func cacheImagesIfNeeded(for message: ChatMessage, maxBytes: Int) async -> [UIImage] {
        let thumbPaths = thumbnailPaths(for: message)
        guard !thumbPaths.isEmpty else { return [] }

        var images: [UIImage] = []
        images.reserveCapacity(thumbPaths.count)

        for thumbPath in thumbPaths {
            if let localURL = thumbPath.localFileURL,
               !FileManager.default.fileExists(atPath: localURL.path) {
                continue
            }

            do {
                let image = try await loadImage(for: thumbPath, maxBytes: maxBytes)
                images.append(image)
            } catch {
                print("이미지 캐시 실패: \(error)")
            }
        }

        return images
    }

    func cachedImage(for path: String) async -> UIImage? {
        guard !path.isEmpty else { return nil }

        if let local = loadLocalImage(from: path) {
            return local
        }

        guard isStoragePath(path) else { return nil }
        return await pipelines.remote.cachedImage(path: path)
    }

    func loadImage(for path: String, maxBytes: Int) async throws -> UIImage {
        if let local = loadLocalImage(from: path) {
            return local
        }

        guard isStoragePath(path) else {
            throw URLError(.badURL)
        }

        return try await pipelines.remote.loadImage(path: path, maxBytes: maxBytes)
    }

    func loadImageData(for path: String, maxBytes: Int) async throws -> Data {
        guard !path.isEmpty else { throw URLError(.badURL) }

        if let fileURL = path.localFileURL {
            return try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        }

        let cacheKey = path as NSString
        if let cached = imageDataCache.object(forKey: cacheKey) {
            let data = cached as Data
            guard data.count <= maxBytes else { throw URLError(.dataLengthExceedsMaximum) }
            return data
        }

        guard isStoragePath(path) else { throw URLError(.badURL) }
        let data = try await imageStorageRepository.fetchImageDataFromStorage(
            image: path,
            location: .roomImage,
            maxBytes: maxBytes
        )
        imageDataCache.setObject(data as NSData, forKey: cacheKey, cost: data.count)
        return data
    }

    func prefetchThumbnails(for messages: [ChatMessage], maxBytes: Int, maxConcurrent: Int) async {
        let paths = messages.flatMap { thumbnailPaths(for: $0) }
        await prefetchImages(paths: paths, maxBytes: maxBytes, maxConcurrent: maxConcurrent)
    }

    func prefetchImages(paths: [String], maxBytes: Int, maxConcurrent: Int) async {
        let normalized = Array(Set(paths.filter { isStoragePath($0) }))
        guard !normalized.isEmpty else { return }
        let items = normalized.map { (path: $0, maxBytes: maxBytes) }
        await pipelines.remote.prefetch(items: items, concurrency: maxConcurrent)
    }

    func storeOutgoingPreview(data: Data, forKey key: String) async {
        try? await pipelines.outgoingPreview.storeImageData(data, path: outgoingPreviewKey(for: key))
    }

    func cachedOutgoingPreview(forKey key: String) async -> UIImage? {
        await pipelines.outgoingPreview.cachedImage(path: outgoingPreviewKey(for: key))
    }

    func preserveLocalPreview(from localPath: String, for remotePath: String) async {
        guard let local = loadLocalImage(from: localPath),
              let data = local.jpegData(compressionQuality: 0.7) else { return }
        // 서버 파일은 수정하지 않는다. 정상 버블의 작은 로컬 cache만 먼저 연결한다.
        try? await pipelines.remote.storeImageData(data, path: remotePath)
    }

    private static func decodePreview(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    func removeCachedImage(for path: String) async {
        imageDataCache.removeObject(forKey: path as NSString)
        await pipelines.remote.removeImage(path: path)
    }

    private func thumbnailPaths(for message: ChatMessage) -> [String] {
        var seen = Set<String>()
        return message.displayableAttachments
            .compactMap { attachment in
                let path = attachment.thumbResourcePath
                guard !path.isEmpty, seen.insert(path).inserted else { return nil }
                return path
            }
    }

    private func isStoragePath(_ path: String) -> Bool {
        !path.isEmpty && !path.isLocalFilePath
    }

    private func loadLocalImage(from path: String) -> UIImage? {
        guard let fileURL = path.localFileURL else { return nil }
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1_024,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    private func outgoingPreviewKey(for key: String) -> String {
        "chatThumb|\(key)"
    }

    private static func makePipelines(
        imageStorageRepository: FirebaseImageStorageRepositoryProtocol
    ) -> ChatAttachmentImagePipelines {
        ChatAttachmentImagePipelines(
            remote: ImageCachePipeline(
                fetcher: { path, maxBytes in
                    try await imageStorageRepository.fetchImageDataFromStorage(
                        image: path,
                        location: .roomImage,
                        maxBytes: maxBytes
                    )
                },
                disk: ImageCacheDiskStore(
                    folderName: "ChatImageCache",
                    maxSizeBytes: 350 * 1024 * 1024,
                    trimTargetBytes: 280 * 1024 * 1024
                ),
                decoder: { decodePreview($0) }
            ),
            outgoingPreview: ImageCachePipeline(
                fetcher: { _, _ in throw URLError(.fileDoesNotExist) },
                memory: ImageCacheMemoryStore(totalCostLimitBytes: 80 * 1024 * 1024),
                disk: ImageCacheDiskStore(folderName: "ThumbCache"),
                decoder: { decodePreview($0) }
            )
        )
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
