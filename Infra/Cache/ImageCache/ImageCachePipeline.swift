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
    private let fileManager = FileManager.default
    private let baseDir: URL

    init(folderName: String = "ImageCache") {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.baseDir = caches.appendingPathComponent(folderName, isDirectory: true)
        try? fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)
    }

    func read(forKey key: String) -> Data? {
        let url = fileURL(forKey: key)
        return try? Data(contentsOf: url)
    }

    func write(data: Data, forKey key: String) {
        let url = fileURL(forKey: key)
        let tmp = url.appendingPathExtension("tmp")

        do {
            try data.write(to: tmp, options: [.atomic])
            if fileManager.fileExists(atPath: url.path) {
                try? fileManager.removeItem(at: url)
            }
            try fileManager.moveItem(at: tmp, to: url)
        } catch {
            // 필요 시 로깅 확장
        }
    }

    func remove(forKey key: String) {
        let url = fileURL(forKey: key)
        try? fileManager.removeItem(at: url)
    }

    private func fileURL(forKey key: String) -> URL {
        let hashed = key.sha256Hex
        return baseDir.appendingPathComponent("\(hashed).bin")
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

enum ImageCachePipelineError: Error {
    case invalidImageData
}

/// 메모리 -> 디스크 -> 네트워크 순으로 이미지를 로딩하는 공용 파이프라인
/// - Note: 동일 키 로딩은 in-flight 레지스트리로 병합합니다.
final class ImageCachePipeline {
    typealias Fetcher = @Sendable (_ path: String, _ maxBytes: Int) async throws -> Data

    private let fetcher: Fetcher
    private let memory: ImageCacheMemoryStore
    private let disk: ImageCacheDiskStore
    private let inflight: ImageCacheInFlightRegistry
    private let prefetchRegistry: ImageCachePrefetchRegistry

    init(
        fetcher: @escaping Fetcher,
        memory: ImageCacheMemoryStore = ImageCacheMemoryStore(),
        disk: ImageCacheDiskStore = ImageCacheDiskStore(),
        inflight: ImageCacheInFlightRegistry = ImageCacheInFlightRegistry(),
        prefetchRegistry: ImageCachePrefetchRegistry = ImageCachePrefetchRegistry()
    ) {
        self.fetcher = fetcher
        self.memory = memory
        self.disk = disk
        self.inflight = inflight
        self.prefetchRegistry = prefetchRegistry
    }

    func loadImage(path: String, maxBytes: Int) async throws -> UIImage {
        let key = canonicalKey(for: path)
        let fetcher = self.fetcher

        if let cached = memory.image(forKey: key) {
            return cached
        }

        if let existing = await inflight.task(for: key) {
            return try await existing.value
        }

        let task = Task<UIImage, Error> { [memory, disk] in
            if let data = await disk.read(forKey: key),
               let diskImage = UIImage(data: data) {
                memory.set(diskImage, forKey: key)
                return diskImage
            }

            let downloaded = try await fetcher(path, maxBytes)
            guard let image = UIImage(data: downloaded) else {
                throw ImageCachePipelineError.invalidImageData
            }

            memory.set(image, forKey: key)
            await disk.write(data: downloaded, forKey: key)
            return image
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
