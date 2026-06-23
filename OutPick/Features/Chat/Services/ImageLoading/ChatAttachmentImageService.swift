//
//  ChatAttachmentImageService.swift
//  OutPick
//
//  Created by Codex on 6/23/26.
//

import Foundation
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

    init(
        imageStorageRepository: FirebaseImageStorageRepositoryProtocol,
        pipelines: ChatAttachmentImagePipelines? = nil
    ) {
        if let pipelines {
            self.pipelines = pipelines
        } else if imageStorageRepository is FirebaseImageStorageRepository {
            self.pipelines = Self.sharedPipelines
        } else {
            self.pipelines = Self.makePipelines(imageStorageRepository: imageStorageRepository)
        }
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

    private func thumbnailPaths(for message: ChatMessage) -> [String] {
        var seen = Set<String>()
        return message.displayableAttachments
            .compactMap { attachment in
                let path = attachment.normalizedThumbPath
                guard !path.isEmpty, seen.insert(path).inserted else { return nil }
                return path
            }
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
                )
            ),
            outgoingPreview: ImageCachePipeline(
                fetcher: { _, _ in throw URLError(.fileDoesNotExist) },
                memory: ImageCacheMemoryStore(totalCostLimitBytes: 80 * 1024 * 1024),
                disk: ImageCacheDiskStore(folderName: "ThumbCache")
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
