import Foundation
import CryptoKit

/// Caches 디렉터리에 이미지 Data를 저장/조회하는 디스크 스토어
/// - Note: 쓰기는 tmp 파일 후 move로 원자적으로 반영합니다.
actor ImageCacheDiskStore {
    enum WriteOutcome: String, Sendable { case success, failure, cancelled, stale }
    private struct DiskEntry {
        let url: URL
        let size: Int64
        let modifiedAt: Date
    }

    private let resources: ImagePipelineResources
    private let fileManager = FileManager.default
    private let baseDir: URL
    private let maxSizeBytes: Int64
    private let trimTargetBytes: Int64
    private var hasScannedSize = false
    private var currentSizeBytes: Int64 = 0
    private var revisions: [String: UInt64] = [:]
    private var globalRevision: UInt64 = 0

    init(
        folderName: String = "ImageCache",
        resources: ImagePipelineResources = .shared,
        maxSizeBytes: Int64 = 300 * 1024 * 1024,
        trimTargetBytes: Int64? = nil
    ) {
        self.resources = resources
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.baseDir = caches.appendingPathComponent(folderName, isDirectory: true)
        self.maxSizeBytes = max(1, maxSizeBytes)
        let defaultTrimTarget = Int64(Double(self.maxSizeBytes) * 0.85)
        let requestedTrimTarget = trimTargetBytes ?? defaultTrimTarget
        self.trimTargetBytes = max(1, min(requestedTrimTarget, self.maxSizeBytes))
        try? fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)
        Task { [weak self] in
            guard let self else { return }
            await self.bootstrap()
        }
    }

    func read(forKey key: String, revision: UInt64 = 0, maxBytes: Int = .max) async -> Data? {
        try? await resources.io.withPermit(kind: .read) { await self.readNow(key: key, revision: revision, maxBytes: maxBytes) }
    }

    func readLease(forKey key: String, revision: UInt64, bypassIOLimit: Bool = false) async throws -> ImageCacheReadLease? {
        if bypassIOLimit { return try readLeaseNow(key: key, revision: revision) }
        return try await resources.io.withPermit(kind: .write) { try await self.readLeaseNow(key: key, revision: revision) }
    }

    private func readLeaseNow(key: String, revision: UInt64) throws -> ImageCacheReadLease? {
        try Task.checkCancellation()
        guard accept(revision: revision, forKey: key) else { return nil }
        let url = fileURL(forKey: key)
        guard let size = fileSize(at: url) else {
            ImageCacheMetrics.shared.mark("disk.lookup", key: key, outcome: "miss")
            return nil
        }
        let lease = try ImageCacheReadLease(source: url)
        touch(url)
        ImageCacheMetrics.shared.mark("disk.lookup", key: key, outcome: "hit", bytes: Int(size))
        return lease
    }

    private func readNow(key: String, revision: UInt64, maxBytes: Int) -> Data? {
        guard !Task.isCancelled else { return nil }
        guard accept(revision: revision, forKey: key) else { return nil }
        let metric = ImageCacheMetrics.shared.begin("diskRead.execution", key: key)
        defer { ImageCacheMetrics.shared.end(metric) }
        let url = fileURL(forKey: key)
        guard let size = fileSize(at: url), size <= Int64(maxBytes),
              let data = try? Data(contentsOf: url) else { return nil }
        touch(url)
        return data
    }

    func write(data: Data, forKey key: String, revision: UInt64 = 0) async {
        await write(payload: .data(data), forKey: key, revision: revision)
    }

    @discardableResult
    func write(payload: ImageCachePayload, forKey key: String, revision: UInt64 = 0) async -> WriteOutcome {
        let metric = ImageCacheMetrics.shared.begin("diskWrite.total", key: key)
        let result: WriteOutcome
        do {
            result = try await resources.io.withPermit(kind: .write) { await self.writeNow(payload: payload, key: key, revision: revision) }
        } catch { result = Task.isCancelled || error is CancellationError ? .cancelled : .failure }
        ImageCacheMetrics.shared.end(metric, outcome: result.rawValue)
        return result
    }

    private func writeNow(payload: ImageCachePayload, key: String, revision: UInt64) -> WriteOutcome {
        guard !Task.isCancelled else { return .cancelled }
        let byteCount: Int
        switch payload {
        case .data(let data): byteCount = data.count
        case .file(let file): byteCount = Int(fileSize(at: file.url) ?? 0)
        }
        guard accept(revision: revision, forKey: key) else { return .stale }
        let metric = ImageCacheMetrics.shared.begin("diskWrite.execution", key: key)
        var outcome = "failure"
        defer { ImageCacheMetrics.shared.end(metric, outcome: outcome, bytes: byteCount) }
        ensureCurrentSizeLoaded()

        let url = fileURL(forKey: key)
        let tmp = url.appendingPathExtension("tmp")
        let oldSize = fileSize(at: url) ?? 0

        do {
            switch payload {
            case .data(let data): try data.write(to: tmp, options: [.atomic])
            case .file(let file):
                try? fileManager.removeItem(at: tmp)
                try fileManager.copyItem(at: file.url, to: tmp)
            }
            if fileManager.fileExists(atPath: url.path) {
                try? fileManager.removeItem(at: url)
            }
            try fileManager.moveItem(at: tmp, to: url)
            touch(url)

            let newSize = fileSize(at: url) ?? Int64(byteCount)
            currentSizeBytes = max(0, currentSizeBytes - oldSize + newSize)
            trimIfNeeded()
            outcome = "success"
            return .success
        } catch {
            try? fileManager.removeItem(at: tmp)
            return .failure
        }
    }

    func remove(forKey key: String, revision: UInt64 = 0) async {
        _ = try? await resources.io.withPermit(kind: .write) { await self.removeNow(key: key, revision: revision) }
    }

    @discardableResult
    func remove(cacheIdentity: String) async -> Bool {
        let revision = ImageCacheRevisionClock.next()
        return (try? await resources.io.withPermit(kind: .write) {
            await self.removeCacheIdentityNow(cacheIdentity, revision: revision)
        }) ?? false
    }

    private func removeNow(key: String, revision: UInt64) {
        guard accept(revision: revision, forKey: key) else { return }
        if revision == 0 { removeFile(forKey: key) }
    }

    private func removeCacheIdentityNow(_ cacheIdentity: String, revision: UInt64) -> Bool {
        let current = max(globalRevision, revisions[cacheIdentity] ?? 0)
        guard revision >= current else { return false }
        revisions[cacheIdentity] = revision
        return removeFile(cacheIdentity: cacheIdentity)
    }

    private func removeFile(forKey key: String) {
        ensureCurrentSizeLoaded()

        _ = removeFile(cacheIdentity: key.sha256Hex)
    }

    private func removeFile(cacheIdentity: String) -> Bool {
        ensureCurrentSizeLoaded()

        let url = fileURL(cacheIdentity: cacheIdentity)
        if let existing = fileSize(at: url) {
            currentSizeBytes = max(0, currentSizeBytes - existing)
        }
        do {
            try fileManager.removeItem(at: url)
            return true
        } catch {
            return !fileManager.fileExists(atPath: url.path)
        }
    }

    func removeAll(revision: UInt64 = 0) async {
        _ = try? await resources.io.withPermit(kind: .write) { await self.removeAllNow(revision: revision) }
    }

    private func removeAllNow(revision: UInt64) {
        guard revision >= globalRevision else { return }
        globalRevision = revision
        // 더 최신인 특정 이미지 저장이 먼저 도착했다면 해당 파일은 보존한다.
        let protectedNames = Set(revisions.filter { $0.value >= revision && revision > 0 }.map { "\($0.key).bin" })
        revisions = revisions.filter { $0.value >= revision && revision > 0 }
        guard let files = try? fileManager.contentsOfDirectory(
            at: baseDir,
            includingPropertiesForKeys: nil
        ) else {
            currentSizeBytes = 0
            hasScannedSize = true
            return
        }
        for file in files {
            if protectedNames.contains(file.lastPathComponent) { continue }
            try? fileManager.removeItem(at: file)
        }
        hasScannedSize = false
        ensureCurrentSizeLoaded()
    }

    /// 무효화와 쓰기가 역순으로 도착해도 이전 세대가 최신 파일을 되살리지 못한다.
    private func accept(revision: UInt64, forKey key: String) -> Bool {
        let cacheIdentity = key.sha256Hex
        let current = max(globalRevision, revisions[cacheIdentity] ?? 0)
        guard revision >= current else { return false }
        if revision > current {
            _ = removeFile(cacheIdentity: cacheIdentity)
            revisions[cacheIdentity] = revision
        }
        return true
    }

    func size(forKey key: String, revision: UInt64) async -> Int? {
        try? await resources.io.withPermit(kind: .read) { await self.sizeNow(key: key, revision: revision) }
    }

    private func sizeNow(key: String, revision: UInt64) -> Int? {
        guard accept(revision: revision, forKey: key) else { return nil }
        let size = fileSize(at: fileURL(forKey: key)).map(Int.init)
        ImageCacheMetrics.shared.mark("disk.lookup", key: key, outcome: size == nil ? "miss" : "hit", bytes: size ?? 0)
        return size
    }

    func copy(forKey key: String, revision: UInt64, to target: URL) async -> Bool {
        (try? await resources.io.withPermit(kind: .write) { await self.copyNow(key: key, revision: revision, target: target) }) ?? false
    }

    private func copyNow(key: String, revision: UInt64, target: URL) -> Bool {
        guard !Task.isCancelled, accept(revision: revision, forKey: key) else { return false }
        do {
            try fileManager.copyItem(at: fileURL(forKey: key), to: target)
            touch(fileURL(forKey: key))
            return true
        } catch { return false }
    }

    private func bootstrap() async {
        _ = try? await resources.io.withPermit(kind: .write) { await self.bootstrapTrimIfNeeded() }
    }

    private func fileURL(forKey key: String) -> URL {
        ImageCacheMetrics.shared.linkCacheKey(key)
        let hashed = key.sha256Hex
        return fileURL(cacheIdentity: hashed)
    }

    private func fileURL(cacheIdentity: String) -> URL {
        baseDir.appendingPathComponent("\(cacheIdentity).bin")
    }

    private func bootstrapTrimIfNeeded() {
        ensureCurrentSizeLoaded()
        trimIfNeeded()
    }

    private func ensureCurrentSizeLoaded() {
        guard !hasScannedSize else { return }
        let metric = ImageCacheMetrics.shared.begin("diskScan.execution")
        defer { ImageCacheMetrics.shared.end(metric) }
        hasScannedSize = true

        let entries = listDiskEntries()
        currentSizeBytes = entries.reduce(Int64(0)) { $0 + $1.size }
    }

    private func trimIfNeeded() {
        guard currentSizeBytes > maxSizeBytes else { return }
        let metric = ImageCacheMetrics.shared.begin("diskTrim.execution")
        defer { ImageCacheMetrics.shared.end(metric) }

        var entries = listDiskEntries()
        guard !entries.isEmpty else {
            currentSizeBytes = 0
            return
        }

        entries.sort { lhs, rhs in lhs.modifiedAt < rhs.modifiedAt }

        for entry in entries {
            do {
                try fileManager.removeItem(at: entry.url)
                ImageCacheMetrics.shared.mark("disk.eviction", key: entry.url.lastPathComponent, outcome: "capacity", bytes: Int(entry.size))
            } catch {
                ImageCacheMetrics.shared.mark("disk.eviction", key: entry.url.lastPathComponent, outcome: "removeFailed")
            }
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


private extension String {
    var sha256Hex: String {
        let digest = SHA256.hash(data: Data(self.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
