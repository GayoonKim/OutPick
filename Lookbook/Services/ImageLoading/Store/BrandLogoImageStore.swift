//
//  BrandLogoImageStore.swift
//  OutPick
//
//  Created by 김가윤 on 12/31/25.
//

import UIKit

/// 브랜드 로고(썸네일/원본) 로딩을 담당하는 스토어
final class BrandLogoImageStore: ImageLoading {

    private let cache: ImageCaching
    private let storage: FirebaseStorageService

    /// Swift Concurrency 환경에서 안전하게 in-flight 작업을 관리하기 위한 레지스트리
    private let inFlightRegistry = InFlightRegistry()

    /// 동일 키에 대한 동시 요청을 하나의 Task로 합치기 위한 Actor
    private actor InFlightRegistry {
        private var tasks: [String: Task<UIImage, Error>] = [:]

        func task(for key: String, create: () -> Task<UIImage, Error>) -> Task<UIImage, Error> {
            if let existing = tasks[key] { return existing }
            let newTask = create()
            tasks[key] = newTask
            return newTask
        }

        func remove(_ key: String) {
            tasks[key] = nil
        }
    }

    init(cache: ImageCaching = MemoryImageCache(), storage: FirebaseStorageService = FirebaseStorageService() ) {
        self.cache = cache
        self.storage = storage
    }

    func loadImage(path: String, cacheKey: String, maxBytes: Int) async throws -> UIImage {
        if let cached = cache.image(forKey: cacheKey) {
            return cached
        }

        // 동일 키 요청은 하나의 Task로 합쳐 중복 다운로드를 방지합니다.
        let registry = inFlightRegistry
        let task = await registry.task(for: cacheKey) { [storage, cache] in
            Task {
                defer {
                    // Task 종료 후 레지스트리에서 제거
                    Task { await registry.remove(cacheKey) }
                }

                let image = try await storage.downloadUIImage(from: path, maxSize: maxBytes)
                cache.setImage(image, forKey: cacheKey)
                return image
            }
        }

        return try await task.value
    }

    func prefetch(items: [(path: String, cacheKey: String, maxBytes: Int)], concurrency: Int) async {
        guard !items.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            var iterator = items.makeIterator()
            var running = 0

            func spawnNext() {
                guard let next = iterator.next() else { return }
                running += 1
                group.addTask { [weak self] in
                    do {
                        _ = try await self?.loadImage(
                            path: next.path,
                            cacheKey: next.cacheKey,
                            maxBytes: next.maxBytes
                        )
                    } catch {
                        // 프리패치에서는 실패를 무시(화면 진입을 막지 않기 위함)
                    }
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
}
