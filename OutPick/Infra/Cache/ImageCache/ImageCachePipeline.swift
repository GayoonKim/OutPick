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

/// 기본 NSCache를 유지하고 채팅 표시 캐시만 명시적 LRU를 선택한다.
final class ImageCacheMemoryStore {
    private let cache = NSCache<NSString, UIImage>()
    private let lru: ImageLRUMemoryStore?

    init(totalCostLimitBytes: Int = 120 * 1024 * 1024, usesLRU: Bool = false) {
        lru = usesLRU ? ImageLRUMemoryStore(maximumBytes: totalCostLimitBytes) : nil
        cache.totalCostLimit = totalCostLimitBytes
    }

    func image(forKey key: String) -> UIImage? {
        let image = lru != nil ? lru?.image(forKey: key) : cache.object(forKey: key as NSString)
        ImageCacheMetrics.shared.linkCacheKey(key)
        ImageCacheMetrics.shared.mark("memory.lookup", key: key, outcome: image == nil ? "miss" : "hit")
        return image
    }

    func set(_ image: UIImage, forKey key: String) {
        if let lru { lru.set(image, forKey: key) }
        else { cache.setObject(image, forKey: key as NSString, cost: image.estimatedBytes) }
        ImageCacheMetrics.shared.linkCacheKey(key)
        ImageCacheMetrics.shared.mark("memory.store", key: key, bytes: image.estimatedBytes)
    }

    func remove(forKey key: String) {
        lru?.remove(forKey: key)
        cache.removeObject(forKey: key as NSString)
        ImageCacheMetrics.shared.mark("memory.remove", key: key, outcome: "explicit")
    }

    var canPrepareDiskImage: Bool { lru?.canPrepareDiskImage ?? false }

    func setIfRoom(_ image: UIImage, forKey key: String) {
        lru?.setIfRoom(image, forKey: key)
    }

    func removeAll() {
        lru?.removeAll()
        cache.removeAllObjects()
        ImageCacheMetrics.shared.mark("memory.removeAll", outcome: "explicit")
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
    case transient
    case memoryOnly
    case memoryAndDisk
}

private extension ImageCacheStorePolicy {
    var debugLabel: String {
        switch self {
        case .transient:
            return "transient"
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
    private let cacheIdentityLock = NSLock()
    private var pathsByCacheIdentity: [String: Set<String>] = [:]
    private static let registryLock = NSLock()
    private static let registry = NSHashTable<ImageCachePipeline>.weakObjects()

    init(
        fetcher: @escaping Fetcher,
        fileFetcher: ImagePipelineProcessor.FileFetcher? = nil,
        memory: ImageCacheMemoryStore = ImageCacheMemoryStore(),
        disk: ImageCacheDiskStore? = nil,
        resources: ImagePipelineResources = .shared,
        usesDirectDiskFileDecoding: Bool = false,
        bypassDirectDiskLimits: Bool = false,
        promotionEncoding: ImageCachePromotionEncoding? = nil,
        decoder: @escaping @Sendable (Data) -> UIImage? = { ImageFileDecoding.image($0) },
        fileDecoder: @escaping @Sendable (URL) -> UIImage? = { ImageFileDecoding.image($0) }
    ) {
        let disk = disk ?? ImageCacheDiskStore(resources: resources)
        self.processor = ImagePipelineProcessor(resources: resources, fetcher: fetcher, fileFetcher: fileFetcher, decoder: decoder, fileDecoder: fileDecoder, usesDirectDiskFileDecoding: usesDirectDiskFileDecoding, bypassDirectDiskLimits: bypassDirectDiskLimits)
        self.memory = memory
        self.disk = disk
        self.resources = resources
        let processor = self.processor
        self.coordinator = ImageLoadCoordinator(
            memory: memory, disk: disk, resources: resources,
            promotion: promotionEncoding.map { encoding in
                { image in try await processor.encoded(image, using: encoding) }
            }
        )
        Self.registryLock.lock()
        Self.registry.add(self)
        Self.registryLock.unlock()
    }

    func cachedImage(path: String) async -> UIImage? {
        rememberCachePath(path)
        return try? await cachedValue(path: path, priority: .visible).image
    }

    var canPrepareDiskImage: Bool { memory.canPrepareDiskImage }

    func prepareDiskImage(path: String) async {
        rememberCachePath(path)
        guard canPrepareDiskImage, !Task.isCancelled else { return }
        let metric = ImageCacheMetrics.shared.begin("chatDiskPreparation", key: path)
        let value = try? await cachedValue(path: path, priority: .diskPreparation)
        ImageCacheMetrics.shared.end(metric, outcome: Task.isCancelled ? "cancelled" : value?.image == nil ? "miss" : "ready")
    }

    /// 표시용 메모리 조회만 수행하며 디스크 읽기·저장 승격은 기존 비동기 경로가 담당한다.
    func cachedMemoryImageImmediately(path: String) -> UIImage? {
        rememberCachePath(path)
        return memory.image(forKey: "imageCache|\(path)")
    }

    func cachedImage(path: String, storePolicy: ImageCacheStorePolicy) async -> UIImage? {
        rememberCachePath(path)
        guard storePolicy != .transient else { return nil }
        guard let image = await cachedImage(path: path), !Task.isCancelled else { return nil }
        if storePolicy == .memoryAndDisk {
            _ = await coordinator.cachedMemoryImage(path: path, promote: true)
        }
        return image
    }

    private func cachedValue(path: String, priority: ImageRequestPriority) async throws -> ImageLoadValue {
        rememberCachePath(path)
        try Task.checkCancellation()
        let request = ImageRequest(path: path, work: .cache)
        if let image = memory.image(forKey: request.cacheKey) {
            ImageCacheMetrics.shared.mark("cache", key: path, outcome: "memory")
            return ImageLoadValue(image: image)
        }
        return try await coordinator.value(for: request, priority: priority, storePolicy: .memoryOnly) { [self] revision in
            // 아직 저장 중인 같은 파일을 miss로 판단해 다시 다운로드하지 않는다.
            // 여기서는 파일/디코드/IO 슬롯을 보유하지 않으므로 저장과 교착하지 않는다.
            try await coordinator.waitForPendingWrite(path: path, revision: revision)
            // fast path 이후 다른 작업이 채운 메모리도 재사용한다.
            if let image = memory.image(forKey: request.cacheKey) { return ImageLoadValue(image: image) }
            return try await processor.cached(disk: disk, key: request.cacheKey, revision: revision)
        }
    }

    func loadImage(path: String, maxBytes: Int) async throws -> UIImage {
        try await loadImage(path: path, maxBytes: maxBytes, storePolicy: .memoryAndDisk, priority: .visible)
    }

    func loadImage(path: String, maxBytes: Int, storePolicy: ImageCacheStorePolicy, priority: ImageRequestPriority) async throws -> UIImage {
        rememberCachePath(path)
        return try await ImageCacheMetrics.shared.request("pipelineRequest", key: path) {
            try Task.checkCancellation()
            let request = ImageRequest(path: path, work: storePolicy == .transient
                ? .transient(maxBytes: maxBytes) : .load(maxBytes: maxBytes))
            if !request.isTransient,
               let image = await coordinator.cachedMemoryImage(path: path, promote: storePolicy == .memoryAndDisk) {
                try Task.checkCancellation()
                ImageCacheMetrics.shared.mark("cache", key: path, outcome: "memory")
                return image
            }
            let value = try await coordinator.value(for: request, priority: priority, storePolicy: storePolicy) { [self] _ in
                if request.isTransient {
                    return try await processor.download(path: path, maxBytes: maxBytes)
                }
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
        rememberCachePath(path)
        let revision = try await coordinator.beginPreparedStore(path: path)
        let value = try await processor.stored(data)
        do {
            try await coordinator.storePrepared(value, path: path, revision: revision)
        } catch { await value.release?(); throw error }
    }

    func flushPendingWrites() async { await coordinator.flushPendingWrites() }

    func removeImage(path: String) async {
        rememberCachePath(path)
        await coordinator.remove(path: path)
    }

    @discardableResult
    func removeExpiredCacheIdentities(_ identities: Set<String>) async -> Bool {
        var succeeded = true
        for identity in identities {
            let paths = rememberedPaths(forCacheIdentity: identity)
            for path in paths { await coordinator.remove(path: path) }
            if !(await disk.remove(cacheIdentity: identity)) { succeeded = false }
        }
        return succeeded
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
        items.forEach { rememberCachePath($0.path) }
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

    private func rememberCachePath(_ path: String) {
        guard !path.isEmpty else { return }
        let identity = "imageCache|\(path)".sha256()
        cacheIdentityLock.lock()
        pathsByCacheIdentity[identity, default: []].insert(path)
        cacheIdentityLock.unlock()
    }

    private func rememberedPaths(forCacheIdentity identity: String) -> Set<String> {
        cacheIdentityLock.lock()
        defer { cacheIdentityLock.unlock() }
        return pathsByCacheIdentity[identity] ?? []
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
