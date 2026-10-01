import CryptoKit
import Foundation

enum ChatMediaExpiryPolicy {
    static let retentionInterval: TimeInterval = 7 * 24 * 60 * 60

    static func isExpired(_ mediaExpiresAt: Date, now: Date) -> Bool {
        mediaExpiresAt <= now
    }
}

struct ChatMediaCacheResource: Hashable, Sendable {
    enum Scope: Hashable, Sendable {
        case attachment(generation: String, mediaExpiresAt: Date?)
        case sharedContent
        case localFile
    }

    let path: String
    let scope: Scope

    static func attachment(path: String, generation: String?, mediaExpiresAt: Date?) -> Self {
        if path.hasPrefix("/") || path.hasPrefix("file://") {
            return .init(path: path, scope: .localFile)
        }
        return .init(path: path, scope: .attachment(generation: generation ?? "", mediaExpiresAt: mediaExpiresAt))
    }

    static func sharedContent(path: String) -> Self {
        .init(path: path, scope: .sharedContent)
    }

    static func localFile(path: String) -> Self {
        .init(path: path, scope: .localFile)
    }

    var isLocalFile: Bool {
        switch scope {
        case .localFile: true
        case .attachment, .sharedContent: path.hasPrefix("/") || path.hasPrefix("file://")
        }
    }

    var mediaExpiresAt: Date? {
        guard case .attachment(_, let expiresAt) = scope else { return nil }
        return expiresAt
    }

    var isExpired: Bool {
        guard let mediaExpiresAt else { return false }
        return ChatMediaExpiryPolicy.isExpired(mediaExpiresAt, now: Date())
    }

    func isAvailable(at now: Date) -> Bool {
        switch scope {
        case .attachment(let generation, let expiresAt):
            guard !generation.isEmpty, let expiresAt else { return false }
            return !ChatMediaExpiryPolicy.isExpired(expiresAt, now: now)
        case .sharedContent, .localFile:
            return true
        }
    }

    var expiryIndexValues: (generation: String, mediaExpiresAt: Date)? {
        guard case .attachment(let generation, let mediaExpiresAt) = scope,
              !generation.isEmpty,
              let mediaExpiresAt else { return nil }
        return (generation, mediaExpiresAt)
    }
}

actor ChatMediaExpiryCacheIndex {
    struct Entry: Codable, Hashable, Sendable {
        let id: String
        let ownerAccountHash: String
        let resourceHash: String
        let imageCacheIdentity: String
        let originalCacheIdentity: String
        let expiresAtMillis: Int64

        var expiresAt: Date { Date(timeIntervalSince1970: Double(expiresAtMillis) / 1_000) }
    }

    static let shared = ChatMediaExpiryCacheIndex(
        root: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ChatMediaExpiry/v1", isDirectory: true)
    )

    private let indexURL: URL
    private var entries: [String: Entry] = [:]
    private var isAvailable = true
    private var needsCacheRecovery = false

    init(root: URL) {
        indexURL = root.appendingPathComponent("index.json")
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            needsCacheRecovery = true
            return
        }
        do {
            let data = try Data(contentsOf: indexURL)
            let decoded = try JSONDecoder().decode([Entry].self, from: data)
            guard Set(decoded.map(\.id)).count == decoded.count else {
                throw CocoaError(.fileReadCorruptFile)
            }
            entries = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
        } catch {
            // 인덱스 손상 시 만료를 알 수 없는 cache를 사용하지 않는다.
            isAvailable = false
            needsCacheRecovery = true
        }
    }

    func requiresCacheRecovery() -> Bool { needsCacheRecovery }

    func completeCacheRecovery() throws {
        try persist([:])
        entries.removeAll()
        needsCacheRecovery = false
        isAvailable = true
    }

    func register(resource: ChatMediaCacheResource, accountID: String, now: Date = Date()) throws {
        guard isAvailable, !needsCacheRecovery else { throw CocoaError(.fileReadCorruptFile) }
        guard case .attachment(let generation, let mediaExpiresAt) = resource.scope,
              !resource.path.isEmpty,
              !accountID.isEmpty,
              !generation.isEmpty,
              let mediaExpiresAt,
              mediaExpiresAt > now else {
            throw URLError(.resourceUnavailable)
        }
        let accountHash = accountID.sha256()
        let resourceHash = "\(accountHash)\0\(resource.path.sha256())\0\(generation.sha256())".sha256()
        let originalIdentity = ChatOriginalFileKey.cacheIdentity(
            accountID: accountID,
            resource: ChatOriginalResource(path: resource.path, version: generation)
        )
        let entry = Entry(
            id: resourceHash,
            ownerAccountHash: accountHash,
            resourceHash: resourceHash,
            imageCacheIdentity: "imageCache|\(resource.path)".sha256(),
            originalCacheIdentity: originalIdentity,
            expiresAtMillis: Int64((mediaExpiresAt.timeIntervalSince1970 * 1_000).rounded(.down))
        )
        if entries[entry.id] == entry { return }
        var next = entries
        next[entry.id] = entry
        try persist(next)
        entries = next
    }

    func expiredEntries(at now: Date) -> [Entry] {
        entries.values.filter { $0.expiresAtMillis <= Int64((now.timeIntervalSince1970 * 1_000).rounded(.down)) }
    }

    func isAvailable(path: String, at now: Date) -> Bool {
        let identity = "imageCache|\(path)".sha256()
        let nowMillis = Int64((now.timeIntervalSince1970 * 1_000).rounded(.down))
        let matching = entries.values.filter { $0.imageCacheIdentity == identity }
        return !matching.isEmpty && matching.contains { $0.expiresAtMillis > nowMillis }
    }

    func removeEntries(ids: Set<String>) throws {
        guard isAvailable else { throw CocoaError(.fileReadCorruptFile) }
        guard !ids.isEmpty else { return }
        var next = entries
        ids.forEach { next.removeValue(forKey: $0) }
        try persist(next)
        entries = next
    }

    private func persist(_ values: [String: Entry]) throws {
        let directory = indexURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(values.values.sorted { $0.id < $1.id })
        try data.write(to: indexURL, options: .atomic)
    }
}
