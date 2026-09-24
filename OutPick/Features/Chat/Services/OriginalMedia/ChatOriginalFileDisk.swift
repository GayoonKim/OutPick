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
    }

    func cachedURL(_ key: ChatOriginalFileKey) -> URL {
        cache.appendingPathComponent(key.account, isDirectory: true)
            .appendingPathComponent("\(key.resource).\(key.version).\(key.ext)")
    }

    func temporaryURL(ext: String) -> URL {
        temporary.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
    }

    func commit(_ url: URL, key: ChatOriginalFileKey) throws -> URL {
        let target = cachedURL(key)
        try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manager.moveItem(at: url, to: target)
        touch(target)
        return target
    }

    func touch(_ url: URL) { try? manager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path) }
    func remove(_ url: URL) { try? manager.removeItem(at: url) }
    func size(_ url: URL) throws -> Int { try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0 }

    func inventory() -> [(ChatOriginalFileKey, URL, Int, Date)] {
        guard let accounts = try? manager.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil) else { return [] }
        return accounts.flatMap { account -> [(ChatOriginalFileKey, URL, Int, Date)] in
            let files = (try? manager.contentsOfDirectory(at: account, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
            return files.compactMap { url in
                let parts = url.lastPathComponent.split(separator: ".").map(String.init)
                guard parts.count == 3,
                      let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                      let size = values.fileSize, size > 0 else { return nil }
                return (ChatOriginalFileKey(account: account.lastPathComponent, resource: parts[0], version: parts[1], ext: parts[2]),
                        url, size, values.contentModificationDate ?? .distantPast)
            }
        }
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
