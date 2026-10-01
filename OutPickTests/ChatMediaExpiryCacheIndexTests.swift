import Foundation
import Testing
@testable import OutPick

struct ChatMediaExpiryCacheIndexTests {
    @Test func attachmentIsUnavailableAtTheExactExpiryBoundary() {
        let expiresAt = Date(timeIntervalSince1970: 2_000_000_000)
        let resource = ChatMediaCacheResource.attachment(
            path: "rooms/room-a/media/photo.jpg",
            generation: "1834567890123456",
            mediaExpiresAt: expiresAt
        )

        #expect(resource.isAvailable(at: expiresAt.addingTimeInterval(-0.001)))
        #expect(!resource.isAvailable(at: expiresAt))
        #expect(!resource.isAvailable(at: expiresAt.addingTimeInterval(0.001)))
    }

    @Test func persistedIndexStillIdentifiesExpiredCacheAfterRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MediaExpiryIndex-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let expiresAt = Date(timeIntervalSince1970: 2_000_000_000)
        let resource = ChatMediaCacheResource.attachment(
            path: "rooms/room-a/media/photo.jpg",
            generation: "1834567890123456",
            mediaExpiresAt: expiresAt
        )
        let first = ChatMediaExpiryCacheIndex(root: root)
        try await first.completeCacheRecovery()
        try await first.register(resource: resource, accountID: "account-a", now: expiresAt.addingTimeInterval(-1))

        let restored = ChatMediaExpiryCacheIndex(root: root)
        let expired = await restored.expiredEntries(at: expiresAt)
        #expect(expired.count == 1)
        #expect(expired[0].imageCacheIdentity != resource.path)
        #expect(!(await restored.isAvailable(path: resource.path, at: expiresAt)))

        let persisted = try Data(contentsOf: root.appendingPathComponent("index.json"))
        #expect(String(decoding: persisted, as: UTF8.self).contains(resource.path) == false)
    }

    @Test func corruptOrDuplicateIndexFailsClosed() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MediaExpiryCorrupt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: root.appendingPathComponent("index.json"))
        let index = ChatMediaExpiryCacheIndex(root: root)
        let resource = ChatMediaCacheResource.attachment(
            path: "rooms/room-a/media/photo.jpg",
            generation: "1834567890123456",
            mediaExpiresAt: Date().addingTimeInterval(60)
        )

        do {
            try await index.register(resource: resource, accountID: "account-a")
            Issue.record("손상된 만료 인덱스가 새 항목 등록을 허용함")
        } catch {}
        #expect(await index.requiresCacheRecovery())
        try await index.completeCacheRecovery()
        #expect(!(await index.requiresCacheRecovery()))
        #expect(await index.expiredEntries(at: .distantFuture).isEmpty)
    }

    @Test func expiredEntriesIncludeOtherAccountsWithoutRemovingValidEntries() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MediaExpiryAccounts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let index = ChatMediaExpiryCacheIndex(root: root)
        try await index.completeCacheRecovery()
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let expired = ChatMediaCacheResource.attachment(
            path: "rooms/a/messages/expired/attachments/1/display",
            generation: "1", mediaExpiresAt: now
        )
        let valid = ChatMediaCacheResource.attachment(
            path: "rooms/b/messages/valid/attachments/2/display",
            generation: "2", mediaExpiresAt: now.addingTimeInterval(60)
        )
        try await index.register(resource: expired, accountID: "signed-out-account", now: now.addingTimeInterval(-60))
        try await index.register(resource: valid, accountID: "current-account", now: now.addingTimeInterval(-60))

        let due = await index.expiredEntries(at: now)
        #expect(due.count == 1)
        try await index.removeEntries(ids: Set(due.map(\.id)))
        #expect(!(await index.isAvailable(path: expired.path, at: now)))
        #expect(await index.isAvailable(path: valid.path, at: now))
    }
}
