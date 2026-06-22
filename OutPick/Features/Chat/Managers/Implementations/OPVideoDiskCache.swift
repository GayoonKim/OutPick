//
//  OPVideoDiskCache.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation
import CryptoKit

/// 비디오 디스크 캐시 (progressive MP4 local caching)
actor OPVideoDiskCache {
    static let shared = OPVideoDiskCache()
    private let dir: URL
    private let capacity: Int64 = 512 * 1024 * 1024 // 512MB
    
    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("Videos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    
    /// Deterministic local file URL for a given logical key.
    func localURL(forKey key: String) -> URL {
        dir.appendingPathComponent(key.sha256() + ".mp4")
    }
    
    /// Returns local file URL if cached.
    func exists(forKey key: String) -> URL? {
        let u = localURL(forKey: key)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }
    
    /// Download and store a remote file to cache; returns the final local URL.
    @discardableResult
    func cache(from remote: URL, key: String) async throws -> URL {
        let tmp = dir.appendingPathComponent(UUID().uuidString + ".part")
        let (data, _) = try await URLSession.shared.data(from: remote)
        try data.write(to: tmp, options: .atomic)
        let dest = localURL(forKey: key)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        try trimIfNeeded()
        return dest
    }
    
    /// Evict old files when capacity exceeded (LRU-ish using modification date).
    private func trimIfNeeded() throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        var entries: [(url: URL, date: Date, size: Int64)] = []
        var total: Int64 = 0
        for u in files {
            let rv = try u.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let d = rv.contentModificationDate ?? Date.distantPast
            let s = Int64(rv.fileSize ?? 0)
            total += s
            entries.append((u, d, s))
        }
        guard total > capacity else { return }
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
            if total <= capacity { break }
        }
    }
}

// MARK: - Utilities
extension String {
    func sha256() -> String {
        let data = Data(self.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
