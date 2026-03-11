//
//  ImageCachePipeline.swift
//  OutPick
//
//  Created by Codex on 2/21/26.
//

import UIKit
import Foundation
import CryptoKit

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

/// Caches 디렉터리에 이미지 Data를 저장/조회하는 디스크 스토어
/// - Note: 쓰기는 tmp 파일 후 move로 원자적으로 반영합니다.
actor ImageCacheDiskStore {
    private struct DiskEntry {
        let url: URL
        let size: Int64
        let modifiedAt: Date
    }

    private let fileManager = FileManager.default
    private let baseDir: URL
    private let maxSizeBytes: Int64
    private let trimTargetBytes: Int64
    private var hasScannedSize = false
    private var currentSizeBytes: Int64 = 0

    init(
        folderName: String = "ImageCache",
        maxSizeBytes: Int64 = 300 * 1024 * 1024,
        trimTargetBytes: Int64? = nil
    ) {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.baseDir = caches.appendingPathComponent(folderName, isDirectory: true)
        self.maxSizeBytes = max(1, maxSizeBytes)
        let defaultTrimTarget = Int64(Double(self.maxSizeBytes) * 0.85)
        let requestedTrimTarget = trimTargetBytes ?? defaultTrimTarget
        self.trimTargetBytes = max(1, min(requestedTrimTarget, self.maxSizeBytes))
        try? fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)
        Task { [weak self] in
            guard let self else { return }
            await self.bootstrapTrimIfNeeded()
        }
    }

    func read(forKey key: String) -> Data? {
        let url = fileURL(forKey: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        touch(url)
        return data
    }

    func write(data: Data, forKey key: String) {
        ensureCurrentSizeLoaded()

        let url = fileURL(forKey: key)
        let tmp = url.appendingPathExtension("tmp")
        let oldSize = fileSize(at: url) ?? 0

        do {
            try data.write(to: tmp, options: [.atomic])
            if fileManager.fileExists(atPath: url.path) {
                try? fileManager.removeItem(at: url)
            }
            try fileManager.moveItem(at: tmp, to: url)
            touch(url)

            let newSize = fileSize(at: url) ?? Int64(data.count)
            currentSizeBytes = max(0, currentSizeBytes - oldSize + newSize)
            trimIfNeeded()
        } catch {
            try? fileManager.removeItem(at: tmp)
            // 필요 시 로깅 확장
        }
    }

    func remove(forKey key: String) {
        ensureCurrentSizeLoaded()

        let url = fileURL(forKey: key)
        if let existing = fileSize(at: url) {
            currentSizeBytes = max(0, currentSizeBytes - existing)
        }
        try? fileManager.removeItem(at: url)
    }

    private func fileURL(forKey key: String) -> URL {
        let hashed = key.sha256Hex
        return baseDir.appendingPathComponent("\(hashed).bin")
    }

    private func bootstrapTrimIfNeeded() {
        ensureCurrentSizeLoaded()
        trimIfNeeded()
    }

    private func ensureCurrentSizeLoaded() {
        guard !hasScannedSize else { return }
        hasScannedSize = true

        let entries = listDiskEntries()
        currentSizeBytes = entries.reduce(Int64(0)) { $0 + $1.size }
    }

    private func trimIfNeeded() {
        guard currentSizeBytes > maxSizeBytes else { return }

        var entries = listDiskEntries()
        guard !entries.isEmpty else {
            currentSizeBytes = 0
            return
        }

        entries.sort { lhs, rhs in lhs.modifiedAt < rhs.modifiedAt }

        for entry in entries {
            try? fileManager.removeItem(at: entry.url)
            currentSizeBytes = max(0, currentSizeBytes - entry.size)
            if currentSizeBytes <= trimTargetBytes {
                break
            }
        }
    }

    private func listDiskEntries() -> [DiskEntry] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: baseDir,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var entries: [DiskEntry] = []
        entries.reserveCapacity(files.count)

        for url in files {
            if url.pathExtension == "tmp" {
                try? fileManager.removeItem(at: url)
                continue
            }
            guard url.pathExtension == "bin" else { continue }

            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]),
                  values.isRegularFile == true else {
                continue
            }

            let fileSize = Int64(values.fileSize ?? 0)
            let modifiedAt = values.contentModificationDate ?? .distantPast
            entries.append(DiskEntry(url: url, size: fileSize, modifiedAt: modifiedAt))
        }
        return entries
    }

    private func fileSize(at url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true else {
            return nil
        }
        return Int64(values.fileSize ?? 0)
    }

    private func touch(_ url: URL) {
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }
}

/// 동일 키의 load 요청을 하나의 Task로 병합하는 레지스트리
actor ImageCacheInFlightRegistry {
    private var tasks: [String: Task<UIImage, Error>] = [:]

    func task(for key: String) -> Task<UIImage, Error>? {
        tasks[key]
    }

    func set(_ task: Task<UIImage, Error>, for key: String) {
        tasks[key] = task
    }

    func remove(_ key: String) {
        tasks.removeValue(forKey: key)
    }
}

/// 동일 키 prefetch 요청을 병합하는 레지스트리
actor ImageCachePrefetchRegistry {
    private var tasks: [String: Task<Void, Never>] = [:]

    func task(for key: String) -> Task<Void, Never>? {
        tasks[key]
    }

    func set(_ task: Task<Void, Never>, for key: String) {
        tasks[key] = task
    }

    func remove(_ key: String) {
        tasks.removeValue(forKey: key)
    }
}

actor ImageCacheAsyncLimiter {
    private var permits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(_ maxPermits: Int) {
        self.permits = max(1, maxPermits)
    }

    func withPermit<T>(_ operation: @Sendable () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }

    private func acquire() async {
        if permits > 0 {
            permits -= 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if !waiters.isEmpty {
            let continuation = waiters.removeFirst()
            continuation.resume()
        } else {
            permits += 1
        }
    }
}

enum ImageCachePipelineError: Error {
    case invalidImageData
}

/// 메모리 -> 디스크 -> 네트워크 순으로 이미지를 로딩하는 공용 파이프라인
/// - Note: 동일 키 로딩은 in-flight 레지스트리로 병합합니다.
final class ImageCachePipeline {
    typealias Fetcher = @Sendable (_ path: String, _ maxBytes: Int) async throws -> Data

    private static let sharedLoadLimiter = ImageCacheAsyncLimiter(6)

    private let fetcher: Fetcher
    private let memory: ImageCacheMemoryStore
    private let disk: ImageCacheDiskStore
    private let inflight: ImageCacheInFlightRegistry
    private let prefetchRegistry: ImageCachePrefetchRegistry
    private let loadLimiter: ImageCacheAsyncLimiter

    init(
        fetcher: @escaping Fetcher,
        memory: ImageCacheMemoryStore = ImageCacheMemoryStore(),
        disk: ImageCacheDiskStore = ImageCacheDiskStore(),
        inflight: ImageCacheInFlightRegistry = ImageCacheInFlightRegistry(),
        prefetchRegistry: ImageCachePrefetchRegistry = ImageCachePrefetchRegistry(),
        loadLimiter: ImageCacheAsyncLimiter = ImageCachePipeline.sharedLoadLimiter
    ) {
        self.fetcher = fetcher
        self.memory = memory
        self.disk = disk
        self.inflight = inflight
        self.prefetchRegistry = prefetchRegistry
        self.loadLimiter = loadLimiter
    }

    func cachedImage(path: String) async -> UIImage? {
        let key = canonicalKey(for: path)
        if let cached = memory.image(forKey: key) {
            return cached
        }
        if let data = await disk.read(forKey: key),
           let diskImage = UIImage(data: data) {
            memory.set(diskImage, forKey: key)
            return diskImage
        }
        return nil
    }

    func loadImage(path: String, maxBytes: Int) async throws -> UIImage {
        let key = canonicalKey(for: path)
        let fetcher = self.fetcher

        if let cached = await cachedImage(path: path) {
            return cached
        }

        if let existing = await inflight.task(for: key) {
            return try await existing.value
        }

        let task = Task<UIImage, Error> { [memory, disk, loadLimiter] in
            try await loadLimiter.withPermit {
                let downloaded = try await fetcher(path, maxBytes)
                guard let image = UIImage(data: downloaded) else {
                    throw ImageCachePipelineError.invalidImageData
                }

                memory.set(image, forKey: key)
                await disk.write(data: downloaded, forKey: key)
                return image
            }
        }

        await inflight.set(task, for: key)
        do {
            let image = try await task.value
            await inflight.remove(key)
            return image
        } catch {
            await inflight.remove(key)
            throw error
        }
    }

    func prefetch(
        items: [(path: String, maxBytes: Int)],
        concurrency: Int
    ) async {
        guard !items.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            var iterator = items.makeIterator()
            var running = 0

            func spawnNext() {
                guard let next = iterator.next() else { return }
                running += 1
                group.addTask { [weak self] in
                    guard let self else { return }
                    await self.prefetchOne(path: next.path, maxBytes: next.maxBytes)
                }
            }

            let initial = min(max(concurrency, 1), items.count)
            for _ in 0..<initial { spawnNext() }

            while running > 0 {
                await group.next()
                running -= 1
                spawnNext()
            }
        }
    }

    private func prefetchOne(path: String, maxBytes: Int) async {
        if Task.isCancelled { return }
        let key = canonicalKey(for: path)

        if memory.image(forKey: key) != nil {
            return
        }

        if let existing = await prefetchRegistry.task(for: key) {
            await existing.value
            return
        }

        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            if Task.isCancelled { return }
            _ = try? await self.loadImage(path: path, maxBytes: maxBytes)
        }

        await prefetchRegistry.set(task, for: key)
        await task.value
        await prefetchRegistry.remove(key)
    }

    private func canonicalKey(for path: String) -> String {
        "imageCache|\(path)"
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

private extension String {
    var sha256Hex: String {
        let digest = SHA256.hash(data: Data(self.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
