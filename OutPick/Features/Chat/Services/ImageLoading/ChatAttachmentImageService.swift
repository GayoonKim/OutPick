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

    func cachedMemoryImageImmediately(for path: String) -> UIImage? {
        // 메인 스레드 즉시 조회에 로컬 파일 읽기·디코딩을 숨기지 않는다.
        guard isStoragePath(path) else { return nil }
        return pipelines.remote.cachedMemoryImageImmediately(path: path)
    }

    var canPrepareDiskImage: Bool { pipelines.remote.canPrepareDiskImage }

    func prepareDiskImage(for path: String) async {
        guard isStoragePath(path) else { return }
        await pipelines.remote.prepareDiskImage(path: path)
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
        try await loadImage(for: path, maxBytes: maxBytes, priority: .visible)
    }

    func loadImage(for path: String, maxBytes: Int, priority: ImageRequestPriority) async throws -> UIImage {
        if let local = loadLocalImage(from: path) {
            return local
        }

        guard isStoragePath(path) else {
            throw URLError(.badURL)
        }

        return try await pipelines.remote.loadImage(path: path, maxBytes: maxBytes, storePolicy: .memoryAndDisk, priority: priority)
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
        let metric = ImageCacheMetrics.shared.begin("chatPreview.preserveLocal", key: remotePath)
        var outcome = "preparationFailed"
        defer { ImageCacheMetrics.shared.end(metric, outcome: outcome) }
        guard let local = loadLocalImage(from: localPath),
              let data = local.jpegData(compressionQuality: 0.7) else { return }
        // 서버 파일은 수정하지 않는다. 정상 버블의 작은 로컬 cache만 먼저 연결한다.
        do {
            try await pipelines.remote.storeImageData(data, path: remotePath)
            // 실제 쓰기 결과는 diskWrite.total로 구분한다. 이 반환은 저장 성공 보장이 아니다.
            outcome = "returned"
        } catch { outcome = Task.isCancelled || error is CancellationError ? "cancelled" : "failed" }
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

    private static func decodePreview(_ url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
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
                fileFetcher: { path, maxBytes, url in
                    try await imageStorageRepository.fetchImageFileFromStorage(image: path, location: .roomImage, maxBytes: maxBytes, to: url)
                },
                memory: ImageCacheMemoryStore(totalCostLimitBytes: 1024 * 1024 * 1024, usesLRU: true),
                disk: ImageCacheDiskStore(
                    folderName: "ChatImageCache",
                    maxSizeBytes: 1024 * 1024 * 1024,
                    trimTargetBytes: 900 * 1024 * 1024
                ),
                usesDirectDiskFileDecoding: true,
                bypassDirectDiskLimits: true,
                decoder: { decodePreview($0) },
                fileDecoder: { decodePreview($0) }
            ),
            outgoingPreview: ImageCachePipeline(
                fetcher: { _, _ in throw URLError(.fileDoesNotExist) },
                memory: ImageCacheMemoryStore(totalCostLimitBytes: 80 * 1024 * 1024),
                disk: ImageCacheDiskStore(folderName: "ThumbCache"),
                decoder: { decodePreview($0) },
                fileDecoder: { decodePreview($0) }
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
