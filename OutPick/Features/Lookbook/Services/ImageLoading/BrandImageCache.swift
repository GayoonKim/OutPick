//
//  BrandImageCache.swift
//  OutPick
//
//  Created by 김가윤 on 12/31/25.
//

import UIKit

/// 브랜드 로고(썸네일/디테일/원본 폴백) 로딩을 담당하는 스토어
final class BrandImageCache: BrandImageCacheProtocol {
    private let pipeline: ImageCachePipeline
    private let httpCache: LookbookHTTPImageCache

    init(
        storage: StorageServiceProtocol = LookbookStorageService(),
        pipeline: ImageCachePipeline? = nil,
        httpCache: LookbookHTTPImageCache = .shared
    ) {
        self.httpCache = httpCache
        self.pipeline = pipeline ?? ImageCachePipeline(
            fetcher: { [storage] path, maxBytes in
                try await storage.downloadImage(from: path, maxSize: maxBytes)
            },
            fileFetcher: { [storage] path, maxBytes, url in
                try await storage.downloadImageFile(from: path, to: url, maxBytes: maxBytes)
            }
        )
    }

    func loadImage(path: String, maxBytes: Int) async throws -> UIImage {
        try await pipeline.loadImage(path: path, maxBytes: maxBytes)
    }

    func cachedRemoteImage(request: LookbookHTTPImageRequest) async -> LookbookHTTPImageCache.CachedImage? {
        await httpCache.cachedImage(for: request)
    }

    func updatedRemoteImage(request: LookbookHTTPImageRequest) async throws -> UIImage {
        try await httpCache.updatedImage(for: request)
    }

    func retryRemoteImage(request: LookbookHTTPImageRequest) async throws -> UIImage {
        await httpCache.resetRetry(for: request)
        return try await httpCache.updatedImage(for: request)
    }

    func prefetchAssets(items: [LookbookAssetImageRequest], concurrency: Int, storePolicy: ImageCacheStorePolicy) async {
        guard !items.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            var iterator = items.makeIterator()
            var running = 0
            func spawnNext() {
                guard !Task.isCancelled, let item = iterator.next() else { return }
                running += 1
                group.addTask { [self] in
                    for path in item.storagePaths {
                        do {
                            _ = try await pipeline.loadImage(path: path, maxBytes: item.maxBytes,
                                                             storePolicy: storePolicy, priority: .prefetch)
                            return
                        } catch { if error is CancellationError || Task.isCancelled { return } }
                    }
                    if let remote = item.remote { _ = try? await httpCache.updatedImage(for: remote) }
                }
            }
            for _ in 0..<min(max(1, concurrency), items.count) { spawnNext() }
            while running > 0 {
                await group.next()
                running -= 1
                spawnNext()
            }
        }
    }

    func storeImageData(_ data: Data, path: String) async throws {
        try await pipeline.storeImageData(data, path: path)
    }

    func removeImage(path: String) async {
        await pipeline.removeImage(path: path)
    }

    func prefetch(
        items: [(path: String, maxBytes: Int)],
        concurrency: Int,
        storePolicy: ImageCacheStorePolicy
    ) async {
        await pipeline.prefetch(
            items: items,
            concurrency: concurrency,
            storePolicy: storePolicy
        )
    }
}
