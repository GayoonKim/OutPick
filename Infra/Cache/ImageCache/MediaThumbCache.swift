//
//  MediaThumbCache.swift
//  OutPick
//
//  Created by 김가윤 on 2/7/26.
//

import UIKit

/// Facade: memory → in-flight → disk decode
actor MediaThumbCache: MediaThumbCaching {
    private let memory: MemoryThumbCache
    private let disk: DiskThumbStore
    private let inflight: ThumbInFlightRegistry

    /// ✅ DI 적용 전 단계에서 임시로 사용할 공유 인스턴스
    static let shared: MediaThumbCaching = {
        let memory = MemoryThumbCache(totalCostLimitBytes: 80 * 1024 * 1024)
        let disk = DiskThumbStore(folderName: "ThumbCache")
        let inflight = ThumbInFlightRegistry()
        return MediaThumbCache(memory: memory, disk: disk, inflight: inflight)
    }()

    init(
        memory: MemoryThumbCache,
        disk: DiskThumbStore,
        inflight: ThumbInFlightRegistry = ThumbInFlightRegistry()
    ) {
        self.memory = memory
        self.disk = disk
        self.inflight = inflight
    }

    // MARK: - Store

    func storeToDisk(data: Data, forKey key: String) async {
        // ✅ Data 그대로 디스크에 저장 (재인코딩/재압축 없음)
        await disk.write(data: data, forKey: key)
    }

    func storeToMemory(image: UIImage, forKey key: String) async {
        // ✅ UIImage를 메모리에만 적재 (즉시 표시 최적)
        memory.set(image, forKey: key)
    }

    // MARK: - Load

    func loadImage(forKey key: String) async -> UIImage? {
        // (1) 메모리 히트면 바로 반환
        if let img = memory.image(forKey: key) {
            return img
        }

        // (2) 동일 key 디스크 read + 디코딩 병합
        let task = await inflight.getOrCreate(forKey: key) { [memory, disk, inflight] in
            defer { Task { await inflight.remove(forKey: key) } }

            guard let data = await disk.read(forKey: key),
                  let img = UIImage(data: data) else {
                return nil
            }

            // 로드 성공 시 메모리에도 올려서 이후는 빠르게
            memory.set(img, forKey: key)
            return img
        }

        return await task.value
    }

    func loadData(forKey key: String) async -> Data? {
        // ✅ 프리페치/백업 용도: 디스크만 조회
        await disk.read(forKey: key)
    }
}
