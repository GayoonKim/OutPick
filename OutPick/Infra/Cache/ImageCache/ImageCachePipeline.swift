//
//  ImageCachePipeline.swift
//  OutPick
//
//  Created by Codex on 2/21/26.
//

import UIKit
import Foundation
import CryptoKit

enum LookbookImageLoadDebugLog {
    static var isEnabled: Bool {
        #if DEBUG
        let processInfo = ProcessInfo.processInfo
        return processInfo.arguments.contains("-LookbookImageLoadMetrics")
            || processInfo.environment["LOOKBOOK_IMAGE_LOAD_METRICS"] == "1"
        #else
        return false
        #endif
    }

    static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        print("[LookbookImageLoad] \(message())")
    }

    static func milliseconds(since startedAt: CFAbsoluteTime) -> String {
        String(format: "%.0fms", (CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
    }

    static func compactPath(_ path: String, maxLength: Int = 72) -> String {
        guard path.count > maxLength else { return path }
        let prefixLength = max(8, maxLength / 3)
        let suffixLength = max(16, maxLength / 2)
        let prefix = path.prefix(prefixLength)
        let suffix = path.suffix(suffixLength)
        return "\(prefix)...\(suffix)"
    }

    static func pathDetails(_ path: String) -> String {
        let compact = compactPath(path)
        if compact == path {
            return "path=\(path)"
        }
        return "path=\(compact) rawPath=\(path)"
    }
}

/// NSCache 기반 공용 메모리 이미지 캐시
final class ImageCacheMemoryStore {
    private let cache = NSCache<NSString, UIImage>()

    init(totalCostLimitBytes: Int = 120 * 1024 * 1024) {
        cache.totalCostLimit = totalCostLimitBytes
    }

    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func set(_ image: UIImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString, cost: image.estimatedBytes)
    }

    func remove(forKey key: String) {
        cache.removeObject(forKey: key as NSString)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}

enum ImageCachePipelineError: Error {
    case invalidImageData
    case reservationTooLarge
    case missingFileTransport
    case imageTooLarge
}

/// 프리패치 시점에 어떤 캐시 계층까지 저장할지 결정합니다.
enum ImageCacheStorePolicy: Equatable {
    case memoryOnly
    case memoryAndDisk
}

private extension ImageCacheStorePolicy {
    var debugLabel: String {
        switch self {
        case .memoryOnly:
            return "memoryOnly"
        case .memoryAndDisk:
            return "memoryAndDisk"
        }
    }
}

/// 기능별 캐시와 고정 fetcher/decoder를 소유하고 동일 요청은 coordinator에 위임한다.
final class ImageCachePipeline {
    typealias Fetcher = @Sendable (_ path: String, _ maxBytes: Int) async throws -> Data

    private let processor: ImagePipelineProcessor
    private let memory: ImageCacheMemoryStore
    private let disk: ImageCacheDiskStore
    private let coordinator: ImageLoadCoordinator
    private let resources: ImagePipelineResources
    private static let registryLock = NSLock()
    private static let registry = NSHashTable<ImageCachePipeline>.weakObjects()

    init(
        fetcher: @escaping Fetcher,
        fileFetcher: ImagePipelineProcessor.FileFetcher? = nil,
        memory: ImageCacheMemoryStore = ImageCacheMemoryStore(),
        disk: ImageCacheDiskStore? = nil,
        resources: ImagePipelineResources = .shared,
        decoder: @escaping @Sendable (Data) -> UIImage? = { ImageFileDecoding.image($0) },
        fileDecoder: @escaping @Sendable (URL) -> UIImage? = { ImageFileDecoding.image($0) }
    ) {
        let disk = disk ?? ImageCacheDiskStore(resources: resources)
        self.processor = ImagePipelineProcessor(resources: resources, fetcher: fetcher, fileFetcher: fileFetcher, decoder: decoder, fileDecoder: fileDecoder)
        self.memory = memory
        self.disk = disk
        self.resources = resources
        self.coordinator = ImageLoadCoordinator(memory: memory, disk: disk, resources: resources)
        Self.registryLock.lock()
        Self.registry.add(self)
        Self.registryLock.unlock()
    }

    func cachedImage(path: String) async -> UIImage? {
        try? await cachedValue(path: path, priority: .visible).image
    }

    private func cachedValue(path: String, priority: ImageRequestPriority) async throws -> ImageLoadValue {
        try Task.checkCancellation()
        let request = ImageRequest(path: path, work: .cache)
        if let image = memory.image(forKey: request.cacheKey) {
            ImageCacheMetrics.shared.mark("cache", key: path, outcome: "memory")
            return ImageLoadValue(image: image)
        }
        return try await coordinator.value(for: request, priority: priority, storePolicy: .memoryOnly) { [self] revision in
            // fast path 이후 다른 작업이 채운 메모리도 재사용한다.
            if let image = memory.image(forKey: request.cacheKey) { return ImageLoadValue(image: image) }
            return try await processor.cached(disk: disk, key: request.cacheKey, revision: revision)
        }
    }

    func loadImage(path: String, maxBytes: Int) async throws -> UIImage {
        try await loadImage(path: path, maxBytes: maxBytes, storePolicy: .memoryAndDisk, priority: .visible)
    }

    func loadImage(path: String, maxBytes: Int, storePolicy: ImageCacheStorePolicy, priority: ImageRequestPriority) async throws -> UIImage {
        try await ImageCacheMetrics.shared.request("pipelineRequest", key: path) {
            try Task.checkCancellation()
            let request = ImageRequest(path: path, work: .load(maxBytes: maxBytes))
            if let image = memory.image(forKey: request.cacheKey) {
                ImageCacheMetrics.shared.mark("cache", key: path, outcome: "memory")
                return image
            }
            let value = try await coordinator.value(for: request, priority: priority, storePolicy: storePolicy) { [self] _ in
                let cached = try await cachedValue(path: path, priority: priority)
                if cached.image != nil {
                    ImageCacheMetrics.shared.mark("cache", key: path, outcome: "local")
                    return cached
                }
                try Task.checkCancellation()
                return try await processor.download(path: path, maxBytes: maxBytes)
            }
            try Task.checkCancellation()
            guard let image = value.image else { throw ImageCachePipelineError.invalidImageData }
            return image
        }
    }

    func storeImageData(_ data: Data, path: String) async throws {
        let value = try await processor.stored(data)
        do {
            guard let image = value.image, let payload = value.payload else { throw ImageCachePipelineError.invalidImageData }
            try await coordinator.store(image: image, payload: payload, path: path)
            await value.release?()
        } catch { await value.release?(); throw error }
    }

    func flushPendingWrites() async { await coordinator.flushPendingWrites() }

    func removeImage(path: String) async {
        await coordinator.remove(path: path)
    }

    func removeAllCachedImages() async {
        await coordinator.removeAll()
    }

    static func removeAllRegisteredCaches() async {
        let pipelines = registeredPipelines()
        await withTaskGroup(of: Void.self) { group in
            for pipeline in pipelines {
                group.addTask { await pipeline.removeAllCachedImages() }
            }
        }
    }

    private static func registeredPipelines() -> [ImageCachePipeline] {
        registryLock.lock()
        defer { registryLock.unlock() }
        return registry.allObjects
    }

    func prefetch(items: [(path: String, maxBytes: Int)], concurrency: Int, storePolicy: ImageCacheStorePolicy = .memoryAndDisk) async {
        guard !items.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            var iterator = items.makeIterator()
            var running = 0
            func spawnNext() {
                guard !Task.isCancelled, let next = iterator.next() else { return }
                running += 1
                group.addTask { [weak self] in
                    guard let self else { return }
                    _ = try? await ImageCacheMetrics.$consumer.withValue("prefetch") {
                        try await self.loadImage(path: next.path, maxBytes: next.maxBytes, storePolicy: storePolicy, priority: .prefetch)
                    }
                }
            }
            for _ in 0..<min(max(concurrency, 1), items.count) { spawnNext() }
            while running > 0 {
                await group.next()
                running -= 1
                spawnNext()
            }
        }
    }


}

private extension UIImage {
    var estimatedBytes: Int {
        let scale = self.scale
        let width = Int(self.size.width * scale)
        let height = Int(self.size.height * scale)
        return max(1, width) * max(1, height) * 4
    }
}
