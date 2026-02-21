//
//  ChatImageCache.swift
//  OutPick
//
//  Created by 김가윤 on 2/7/26.
//

import UIKit

/// Facade: memory → in-flight → disk decode
actor ChatImageCache: ChatImageCacheProtocol {
    private let memory: ImageCacheMemoryStore
    private let disk: ImageCacheDiskStore
    private let inflight: ImageCacheInFlightRegistry

    /// ✅ DI 적용 전 단계에서 임시로 사용할 공유 인스턴스
    static let shared: ChatImageCacheProtocol = {
        let memory = ImageCacheMemoryStore(totalCostLimitBytes: 80 * 1024 * 1024)
        let disk = ImageCacheDiskStore(folderName: "ThumbCache")
        let inflight = ImageCacheInFlightRegistry()
        return ChatImageCache(memory: memory, disk: disk, inflight: inflight)
    }()

    init(
        memory: ImageCacheMemoryStore,
        disk: ImageCacheDiskStore,
        inflight: ImageCacheInFlightRegistry = ImageCacheInFlightRegistry()
    ) {
        self.memory = memory
        self.disk = disk
        self.inflight = inflight
    }

    // MARK: - Store

    func storeToDisk(data: Data, forKey key: String) async {
        // ✅ Data 그대로 디스크에 저장 (재인코딩/재압축 없음)
        await disk.write(data: data, forKey: canonicalKey(for: key))
    }

    func storeToMemory(image: UIImage, forKey key: String) async {
        // ✅ UIImage를 메모리에만 적재 (즉시 표시 최적)
        memory.set(image, forKey: canonicalKey(for: key))
    }

    // MARK: - Load

    func loadImage(forKey key: String) async -> UIImage? {
        let cacheKey = canonicalKey(for: key)

        // (1) 메모리 히트면 바로 반환
        if let img = memory.image(forKey: cacheKey) {
            return img
        }

        // (2) 동일 key 디스크 read + 디코딩 병합
        if let existing = await inflight.task(for: cacheKey) {
            return try? await existing.value
        }

        let task = Task<UIImage, Error> { [memory, disk] in
            guard let data = await disk.read(forKey: cacheKey),
                  let img = UIImage(data: data) else {
                throw ChatImageCacheError.cacheMiss
            }
            memory.set(img, forKey: cacheKey)
            return img
        }

        await inflight.set(task, for: cacheKey)
        do {
            let image = try await task.value
            await inflight.remove(cacheKey)
            return image
        } catch {
            await inflight.remove(cacheKey)
            return nil
        }
    }

    func loadData(forKey key: String) async -> Data? {
        // ✅ 프리페치/백업 용도: 디스크만 조회
        await disk.read(forKey: canonicalKey(for: key))
    }

    private func canonicalKey(for key: String) -> String {
        "chatThumb|\(key)"
    }
}

private enum ChatImageCacheError: Error {
    case cacheMiss
}
