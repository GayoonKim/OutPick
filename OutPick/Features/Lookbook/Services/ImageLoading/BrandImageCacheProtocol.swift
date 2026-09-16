//
//  BrandImageCacheProtocol.swift
//  OutPick
//
//  Created by 김가윤 on 12/31/25.
//

import UIKit

protocol BrandImageCacheProtocol {
    /// 캐시 우선으로 이미지를 로드합니다.
    func loadImage(path: String, maxBytes: Int) async throws -> UIImage

    /// Storage 후보가 모두 실패했을 때 외부 URL의 저장본과 검증 결과를 제공한다.
    func cachedRemoteImage(request: LookbookHTTPImageRequest) async -> LookbookHTTPImageCache.CachedImage?
    func updatedRemoteImage(request: LookbookHTTPImageRequest) async throws -> UIImage
    func retryRemoteImage(request: LookbookHTTPImageRequest) async throws -> UIImage
    func prefetchAssets(items: [LookbookAssetImageRequest], concurrency: Int, storePolicy: ImageCacheStorePolicy) async

    /// 같은 Storage path에 파일이 덮어써진 경우, 새 데이터를 캐시에 즉시 반영합니다.
    func storeImageData(_ data: Data, path: String) async throws

    /// 같은 Storage path가 덮어써졌거나 더 이상 유효하지 않을 때 캐시를 비웁니다.
    func removeImage(path: String) async

    /// 여러 이미지를 병렬로 프리패치합니다. (실패는 무시 가능)
    func prefetch(
        items: [(path: String, maxBytes: Int)],
        concurrency: Int,
        storePolicy: ImageCacheStorePolicy
    ) async
}

extension BrandImageCacheProtocol {
    func prefetchAssets(items: [LookbookAssetImageRequest], concurrency: Int, storePolicy: ImageCacheStorePolicy) async {
        guard !items.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            var iterator = items.makeIterator()
            var running = 0
            func spawnNext() {
                guard !Task.isCancelled, let item = iterator.next() else { return }
                running += 1
                group.addTask {
                    for path in item.storagePaths {
                        do { _ = try await loadImage(path: path, maxBytes: item.maxBytes); return }
                        catch { if error is CancellationError || Task.isCancelled { return } }
                    }
                    if let remote = item.remote { _ = try? await updatedRemoteImage(request: remote) }
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

    func cachedRemoteImage(request: LookbookHTTPImageRequest) async -> LookbookHTTPImageCache.CachedImage? {
        await LookbookHTTPImageCache.shared.cachedImage(for: request)
    }

    func updatedRemoteImage(request: LookbookHTTPImageRequest) async throws -> UIImage {
        try await LookbookHTTPImageCache.shared.updatedImage(for: request)
    }

    func retryRemoteImage(request: LookbookHTTPImageRequest) async throws -> UIImage {
        await LookbookHTTPImageCache.shared.resetRetry(for: request)
        return try await LookbookHTTPImageCache.shared.updatedImage(for: request)
    }

    /// 기본 프리패치는 메모리와 디스크를 함께 사용합니다.
    func prefetch(items: [(path: String, maxBytes: Int)], concurrency: Int) async {
        await prefetch(
            items: items,
            concurrency: concurrency,
            storePolicy: .memoryAndDisk
        )
    }
}
