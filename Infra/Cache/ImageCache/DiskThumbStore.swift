//
//  DiskThumbStore.swift
//  OutPick
//
//  Created by 김가윤 on 2/7/26.
//

import Foundation

/// 디스크 저장소 (Caches/ThumbCache/<sha>.jpg)
/// - 원자적 write(tmp → move)
actor DiskThumbStore {
    private let fileManager = FileManager.default
    private let baseDir: URL

    init(folderName: String = "ThumbCache") {
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
            // 필요하면 로깅
        }
    }

    func remove(forKey key: String) {
        let url = fileURL(forKey: key)
        try? fileManager.removeItem(at: url)
    }

    private func fileURL(forKey key: String) -> URL {
        baseDir.appendingPathComponent("\(key).jpg")
    }
}
