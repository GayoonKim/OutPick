import Foundation
import Darwin
import Testing
@testable import OutPick

struct GRDBChatMessageAdmissionTests {
    @Test func sustainedBurstsKeepNewestCacheContiguousAcrossPruning() async throws {
        let store = GRDBChatMessageStore(database: try TemporaryAppDatabase.make())
        let session = ChatMessageCacheSession()
        let queue = ChatMessageSaveQueue(session: session)
        let start = ProcessInfo.processInfo.systemUptime
        for wave in 0..<60 {
            for offset in 1...1_000 {
                let seq = Int64(wave * 1_000 + offset)
                await queue.enqueue(GRDBTestFixtures.message(id: "sustained-\(seq)", seq: seq), save: {
                    try await store.saveChatMessages([$0], accountID: "account-1", session: session)
                }, confirm: { _ in })
            }
            await queue.waitUntilIdle()
            let rows = try await store.fetchRecentMessages(inRoom: "room-1", limit: 4_000)
            let upper = Int64((wave + 1) * 1_000)
            #expect(rows.last?.seq == upper)
            #expect(rows.count <= 3_300)
            #expect(rows.map(\.seq) == Array((upper - Int64(rows.count) + 1)...upper))
            if wave % 10 == 9 {
                print("CACHE_QA sustained=\(upper) elapsedSeconds=\(ProcessInfo.processInfo.systemUptime - start) resident=\(residentBytes()) cacheRows=\(rows.count)")
            }
        }
    }
    @Test func realDatabaseBurstPersistsEveryMessage() async throws {
        let store = GRDBChatMessageStore(database: try TemporaryAppDatabase.make())
        let session = ChatMessageCacheSession()
        let queue = ChatMessageSaveQueue(session: session)
        let start = ProcessInfo.processInfo.systemUptime
        let before = residentBytes()
        for seq in 1...3_000 {
            let message = GRDBTestFixtures.message(id: "burst-\(seq)", seq: Int64(seq))
            await queue.enqueue(message, save: {
                try await store.saveChatMessages([$0], accountID: "account-1", session: session)
            }, confirm: { _ in })
        }
        await queue.waitUntilIdle()
        let rows = try await store.fetchRecentMessages(inRoom: "room-1", limit: 3_000)
        #expect(rows.count == 3_000)
        #expect(rows.map(\.seq) == Array(1...3_000).map(Int64.init))
        print("CACHE_QA burst=3000 elapsedSeconds=\(ProcessInfo.processInfo.systemUptime - start) residentBefore=\(before) residentAfter=\(residentBytes())")
    }

    private func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }
    @Test func authoritativeRepairReplacesOnlyConflictingIdentity() async throws {
        let database = try TemporaryAppDatabase.make()
        let store = GRDBChatMessageStore(database: database)
        let old = GRDBTestFixtures.message(id: "stale", seq: 1)
        let canonical = GRDBTestFixtures.message(id: "canonical", seq: 1)
        try await store.saveChatMessages([old])
        try await store.saveAuthoritativeIdentityRepair([canonical], accountID: "account-1", session: ChatMessageCacheSession())
        #expect(try await store.fetchMessage(id: old.ID, inRoom: old.roomID) == nil)
        #expect(try await store.fetchMessage(id: canonical.ID, inRoom: canonical.roomID)?.seq == 1)
    }
    @Test func deletionCommittedBeforeStaleWriteCannotRestoreBody() async throws {
        let database = try TemporaryAppDatabase.make()
        let store = GRDBChatMessageStore(database: database, currentAccountID: { "account-1" })
        let deletion = GRDBChatDeletionSyncStore(database: database)
        let original = GRDBTestFixtures.message(id: "target", seq: 1)
        try await store.saveChatMessages([original])
        _ = try await deletion.apply([ChatDeletionDelta(messageID: original.ID, roomID: original.roomID,
            seq: 1, revision: 1, deletedAt: nil)], accountID: "account-1", roomID: original.roomID)
        try await store.saveChatMessages([original])
        let restored = try #require(try await store.fetchMessage(id: original.ID, inRoom: original.roomID))
        #expect(restored.isDeleted)
        #expect(restored.msg == nil)
        #expect(restored.attachments.isEmpty)
    }

    @Test func invalidatedSessionCannotCommit() async throws {
        let database = try TemporaryAppDatabase.make()
        let store = GRDBChatMessageStore(database: database)
        let session = ChatMessageCacheSession()
        session.invalidate()
        let message = GRDBTestFixtures.message(id: "late", seq: 1)
        await #expect(throws: CancellationError.self) {
            try await store.saveChatMessages([message], accountID: "account-1", session: session)
        }
        #expect(try await store.fetchMessage(id: message.ID, inRoom: message.roomID) == nil)
    }
}
