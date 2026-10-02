import Foundation
import GRDB
@testable import OutPick

enum SearchStoreFixture {
    static func scope(account: String = "account-1", room: String = "room-1") throws -> ChatSearchScope {
        try ChatSearchScope(identity: ChatSearchSessionIdentity(sessionID: UUID(), accountID: account,
            accountEpoch: UUID(), roomID: room, generation: 1), keyword: "ㅋㅋ", upperSeq: 10_000, source: .serverIndex)
    }
    static func hit(_ id: String, _ seq: Int64, author: String = "author") -> ChatSearchResultMetadata {
        ChatSearchResultMetadata(messageID: id, seq: seq, senderUID: author)
    }
    static func cursor(_ value: String) -> ChatSearchCursor { ChatSearchCursor(opaqueValue: Data(value.utf8)) }
    static func commit(_ store: GRDBChatSearchStore, _ scope: ChatSearchScope,
                       hits: [ChatSearchResultMetadata], after: ChatSearchCursor? = nil,
                       next: String = "next", revision: UInt64 = 0, exhausted: Bool = false) async throws -> ChatSearchStoredState {
        try await store.commitPage(identity: scope.identity, visibilityRevision: revision, expectedCursor: after,
                                   hits: hits, nextCursor: cursor(next), isExhausted: exhausted)
    }
    static func delta(_ id: String, _ revision: Int64) -> ChatDeletionDelta {
        ChatDeletionDelta(messageID: id, roomID: "room-1", seq: revision, revision: revision, deletedAt: nil)
    }
    static func fail(_ database: AppDatabase, on event: String) async throws {
        try await database.dbPool.write { db in
            try db.execute(sql: "CREATE TRIGGER fail_search \(event) BEGIN SELECT RAISE(ABORT, 'forced search failure'); END")
        }
    }
    static func clearFailure(_ database: AppDatabase) async throws {
        try await database.dbPool.write { db in try db.execute(sql: "DROP TRIGGER fail_search") }
    }
}

actor SearchWriteBarrier {
    private var resume: CheckedContinuation<Void, Never>?
    private var entered: CheckedContinuation<Void, Never>?
    func suspend() async {
        await withCheckedContinuation { resume = $0; entered?.resume(); entered = nil }
    }
    func waitUntilSuspended() async {
        if resume != nil { return }
        await withCheckedContinuation { entered = $0 }
    }
    func release() { resume?.resume(); resume = nil }
}

actor SearchRecoveryRepository: ChatDeletionSyncRepositoryProtocol {
    let head: Int64
    let rows: [ChatDeletionDelta]
    private(set) var requestedIDs: [[String]] = []
    private(set) var pageQueries = 0
    init(head: Int64, rows: [ChatDeletionDelta]) { self.head = head; self.rows = rows }
    func headRevision(roomID: String) async throws -> Int64 { head }
    func deltas(roomID: String, afterRevision: Int64, limit: Int) async throws -> [ChatDeletionDelta] {
        pageQueries += 1
        return [] // journal 유실을 재현하고 실제 복구 경로로 들어간다.
    }
    func deltas(roomID: String, messageIDs: [String]) async throws -> [ChatDeletionDelta] {
        requestedIDs.append(messageIDs)
        return rows.filter { messageIDs.contains($0.messageID) }
    }
}

struct SearchNoopCleaner: ChatDeletionMediaCleaning {
    func clean(_ item: ChatDeletionCleanupItem) async throws {}
}
