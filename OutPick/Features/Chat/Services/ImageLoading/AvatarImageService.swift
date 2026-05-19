//
//  AvatarImageService.swift
//  OutPick
//
//  Created by Codex on 3/24/26.
//

import Foundation
import UIKit

final class AvatarImageService: ChatAvatarImageManaging {
    static let shared = AvatarImageService()

    private static let sharedPipeline = makePipeline(
        imageStorageRepository: FirebaseImageStorageRepository.shared
    )

    private let pipeline: ImageCachePipeline

    init(
        imageStorageRepository: FirebaseImageStorageRepositoryProtocol = FirebaseImageStorageRepository.shared,
        pipeline: ImageCachePipeline? = nil
    ) {
        if let pipeline {
            self.pipeline = pipeline
        } else if imageStorageRepository is FirebaseImageStorageRepository {
            self.pipeline = Self.sharedPipeline
        } else {
            self.pipeline = Self.makePipeline(imageStorageRepository: imageStorageRepository)
        }
    }

    func cachedAvatar(for path: String) async -> UIImage? {
        guard !path.isEmpty else { return nil }

        if let local = loadLocalImage(from: path) {
            return local
        }

        guard isStoragePath(path) else { return nil }
        return await pipeline.cachedImage(path: path)
    }

    func loadAvatar(for path: String, maxBytes: Int) async throws -> UIImage {
        if let local = loadLocalImage(from: path) {
            return local
        }

        guard isStoragePath(path) else {
            throw URLError(.badURL)
        }

        return try await pipeline.loadImage(path: path, maxBytes: maxBytes)
    }

    func prefetchAvatars(paths: [String], maxBytes: Int, maxConcurrent: Int) async {
        let normalized = Array(Set(paths.filter { isStoragePath($0) }))
        guard !normalized.isEmpty else { return }
        let items = normalized.map { (path: $0, maxBytes: maxBytes) }
        await pipeline.prefetch(items: items, concurrency: maxConcurrent)
    }

    func storeAvatarDataToCache(_ data: Data, for path: String) async throws {
        guard isStoragePath(path) else { return }
        try await pipeline.storeImageData(data, path: path)
    }

    func removeCachedAvatar(for path: String) async {
        guard isStoragePath(path) else { return }
        await pipeline.removeImage(path: path)
    }

    private static func makePipeline(
        imageStorageRepository: FirebaseImageStorageRepositoryProtocol
    ) -> ImageCachePipeline {
        ImageCachePipeline(
            fetcher: { path, maxBytes in
                try await imageStorageRepository.fetchImageDataFromStorage(
                    image: path,
                    location: .profileImage,
                    maxBytes: maxBytes
                )
            },
            disk: ImageCacheDiskStore(
                folderName: "AvatarImageCache",
                maxSizeBytes: 100 * 1024 * 1024,
                trimTargetBytes: 75 * 1024 * 1024
            )
        )
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
