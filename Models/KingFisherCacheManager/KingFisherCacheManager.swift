//
//  KingFisherCacheManager.swift
//  OutPick
//
//  Created by 김가윤 on 7/23/25.
//


import UIKit
import Kingfisher

// Coalesce concurrent fetches for the same cache key
private actor _KFInflightRegistry {
    private var tasks: [String: Task<UIImage, Error>] = [:]
    
    func task(for key: String) -> Task<UIImage, Error>? { tasks[key] }
    func set(_ task: Task<UIImage, Error>, for key: String) { tasks[key] = task }
    func remove(_ key: String) { tasks.removeValue(forKey: key) }
}

final class KingFisherCacheManager {
    static let shared = KingFisherCacheManager()
    
    // In-flight task registry to deduplicate concurrent loads
    private let inflight = _KFInflightRegistry()
    private init() {}

    /// Kingfisher 캐시에서 이미지 비동기 로드
    func loadImage(named name: String) async -> UIImage? {
        if let image = KingfisherManager.shared.cache.retrieveImageInMemoryCache(forKey: name) {
            return image
        }
        
        if let image = try? await KingfisherManager.shared.cache.retrieveImageInDiskCache(forKey: name) {
            return image
        }

        return nil
    }

    /// 이미지를 메모리 & 디스크 캐시에 저장
    func storeImage(_ image: UIImage, forKey key: String) {
        KingfisherManager.shared.cache.store(image, forKey: key)
    }

    /// 캐시에서 이미지 제거
    func removeImage(forKey key: String) {
        KingfisherManager.shared.cache.removeImage(forKey: key)
    }

    /// 동일 의미의 새 이름 (기존 loadImage(named:)을 보존하면서 가독성 개선)
    func image(forKey key: String) async -> UIImage? {
        return await loadImage(named: key)
    }

    /// 주어진 키가 메모리/디스크 캐시에 존재하는지 확인
    func isCached(_ key: String) async -> Bool {
        if KingfisherManager.shared.cache.retrieveImageInMemoryCache(forKey: key) != nil {
            return true
        }
        if (try? await KingfisherManager.shared.cache.retrieveImageInDiskCache(forKey: key)) != nil {
            return true
        }
        return false
    }

    /// 캐시에 있으면 반환, 없으면 fetch()로 가져와 캐시에 저장 후 반환.
    /// 동시에 여러 곳에서 같은 키로 호출되어도 네트워크/디스크 접근을 1회로 병합합니다.
    func loadOrFetchImage(forKey key: String,
                          fetch: @escaping () async throws -> UIImage) async throws -> UIImage {
        // 1) 메모리 히트
        if let mem = KingfisherManager.shared.cache.retrieveImageInMemoryCache(forKey: key) {
            print(#function, "MEMORY HIT for \(key)")
            return mem
        }
        // 2) 디스크 히트
        if let disk = try? await KingfisherManager.shared.cache.retrieveImageInDiskCache(forKey: key) {
            print(#function, "MEMORY HIT for \(key)")
            return disk
        }
        // 3) in-flight 병합
        if let existing = await inflight.task(for: key) {
            return try await existing.value
        }
        let task = Task<UIImage, Error> {
            let img = try await fetch()
            try await KingfisherManager.shared.cache.store(img, forKey: key)
            return img
        }
        await inflight.set(task, for: key)
        do {
            let result = try await task.value
            await inflight.remove(key)
            return result
        } catch {
            await inflight.remove(key)
            throw error
        }
    }

    /// 여러 키를 한 번에 캐시 웜업 (병렬). 이미 캐시된 키는 건너뜀.
    func warm(keys: [String],
              fetcher: @escaping (String) async throws -> UIImage) async {
        await withTaskGroup(of: Void.self) { group in
            for key in keys {
                group.addTask { [weak self] in
                    guard let self = self else { return }
                    if await self.isCached(key) { return }
                    _ = try? await self.loadOrFetchImage(forKey: key) {
                        try await fetcher(key)
                    }
                }
            }
        }
    }
}
