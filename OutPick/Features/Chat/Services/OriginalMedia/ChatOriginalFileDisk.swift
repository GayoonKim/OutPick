import Foundation

struct ChatOriginalFileKey: Hashable, Sendable {
    let account: String
    let resource: String
    let version: String
    let ext: String

    init(accountID: String, resource: ChatOriginalResource) {
        account = accountID.sha256()
        self.resource = resource.path.sha256()
        version = resource.version.sha256()
        ext = resource.fileExtension
    }

    init(account: String, resource: String, version: String, ext: String) {
        self.account = account; self.resource = resource; self.version = version; self.ext = ext
    }

    static func cacheIdentity(accountID: String, resource: ChatOriginalResource) -> String {
        let key = ChatOriginalFileKey(accountID: accountID, resource: resource)
        return "\(key.account)/\(key.resource)/\(key.version)/\(key.ext)".sha256()
    }
}

/// 파일 접근은 ChatOriginalFileStore actor 안에서만 수행한다. 표시 캐시와 outbox는 수정하지 않는다.
final class ChatOriginalFileDisk {
    let root: URL
    let cache: URL
    let temporary: URL
    private let manager = FileManager.default

    init(root: URL) throws {
        self.root = root
        cache = root.appendingPathComponent("cache", isDirectory: true)
        temporary = root.appendingPathComponent("temporary", isDirectory: true)
        try manager.createDirectory(at: cache, withIntermediateDirectories: true)
        try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
        // 앱 종료로 남은 이 저장소의 임시 파일만 제거한다.
        for url in try manager.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil) {
            try manager.removeItem(at: url)
        }
        removeUnindexedFiles()
    }

    func cachedURL(_ key: ChatOriginalFileKey) -> URL {
        cache.appendingPathComponent(key.account, isDirectory: true)
            .appendingPathComponent("\(key.resource).\(key.version).\(key.ext)")
    }

    func temporaryURL(ext: String) -> URL {
        temporary.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
    }

    func commit(_ url: URL, key: ChatOriginalFileKey, mediaExpiresAt: Date) throws -> URL {
        let target = cachedURL(key)
        try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let metadataURL = expiryURL(for: target)
        if manager.fileExists(atPath: target.path) { try manager.removeItem(at: target) }
        if manager.fileExists(atPath: metadataURL.path) { try manager.removeItem(at: metadataURL) }
        try manager.moveItem(at: url, to: target)
        do {
            let metadata = ExpiryMetadata(expiresAtMillis: Int64((mediaExpiresAt.timeIntervalSince1970 * 1_000).rounded(.down)))
            try JSONEncoder().encode(metadata).write(to: metadataURL, options: .atomic)
        } catch {
            try? manager.removeItem(at: target)
            throw error
        }
        touch(target)
        return target
    }

    func touch(_ url: URL) { try? manager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path) }
    func remove(_ url: URL) {
        try? manager.removeItem(at: url)
        try? manager.removeItem(at: expiryURL(for: url))
    }
    func size(_ url: URL) throws -> Int { try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0 }

    func inventory() -> [(ChatOriginalFileKey, URL, Int, Date, Date)] {
        guard let accounts = try? manager.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil) else { return [] }
        return accounts.flatMap { account -> [(ChatOriginalFileKey, URL, Int, Date, Date)] in
            let files = (try? manager.contentsOfDirectory(at: account, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
            return files.compactMap { url in
                let parts = url.lastPathComponent.split(separator: ".").map(String.init)
                guard parts.count == 3,
                      let metadata = try? Data(contentsOf: expiryURL(for: url)),
                      let expiry = try? JSONDecoder().decode(ExpiryMetadata.self, from: metadata),
                      let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                      let size = values.fileSize, size > 0 else { return nil }
                return (ChatOriginalFileKey(account: account.lastPathComponent, resource: parts[0], version: parts[1], ext: parts[2]),
                        url, size, values.contentModificationDate ?? .distantPast,
                        Date(timeIntervalSince1970: Double(expiry.expiresAtMillis) / 1_000))
            }
        }
    }

    func removeExpiredFiles(at now: Date, excluding protectedKeys: Set<ChatOriginalFileKey>) -> Bool {
        let entries = inventory().filter { $0.4 <= now && !protectedKeys.contains($0.0) }
        var succeeded = true
        for (_, url, _, _, _) in entries {
            do {
                if manager.fileExists(atPath: url.path) { try manager.removeItem(at: url) }
                let metadata = expiryURL(for: url)
                if manager.fileExists(atPath: metadata.path) { try manager.removeItem(at: metadata) }
            } catch {
                succeeded = false
            }
        }
        succeeded = removeOrphanMetadata() && succeeded
        return succeeded
    }

    private func removeUnindexedFiles() {
        guard let accounts = try? manager.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil) else { return }
        for account in accounts {
            guard let files = try? manager.contentsOfDirectory(at: account, includingPropertiesForKeys: nil) else { continue }
            for url in files {
                let parts = url.lastPathComponent.split(separator: ".")
                guard parts.count == 3 else { continue }
                let metadataURL = expiryURL(for: url)
                guard let data = try? Data(contentsOf: metadataURL),
                      (try? JSONDecoder().decode(ExpiryMetadata.self, from: data)) != nil else {
                    try? manager.removeItem(at: url)
                    try? manager.removeItem(at: metadataURL)
                    continue
                }
            }
        }
        _ = removeOrphanMetadata()
    }

    @discardableResult
    private func removeOrphanMetadata() -> Bool {
        guard let accounts = try? manager.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil) else { return true }
        var succeeded = true
        for account in accounts {
            guard let files = try? manager.contentsOfDirectory(at: account, includingPropertiesForKeys: nil) else { continue }
            for url in files where url.lastPathComponent.hasSuffix(".expiry.json") {
                let targetPath = String(url.path.dropLast(".expiry.json".count))
                guard !manager.fileExists(atPath: targetPath) else { continue }
                do { try manager.removeItem(at: url) } catch { succeeded = false }
            }
        }
        return succeeded
    }

    private struct ExpiryMetadata: Codable {
        let expiresAtMillis: Int64
    }

    private func expiryURL(for fileURL: URL) -> URL {
        fileURL.appendingPathExtension("expiry.json")
    }

    static func bytes(in roots: [URL]) -> Int {
        roots.reduce(0) { sum, root in
            guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return sum }
            return sum + files.compactMap { $0 as? URL }.reduce(0) { value, url in
                guard let info = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), info.isRegularFile == true else { return value }
                return value + (info.fileSize ?? 0)
            }
        }
    }
}
