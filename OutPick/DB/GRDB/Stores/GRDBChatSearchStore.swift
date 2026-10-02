import Foundation
import GRDB

final class GRDBChatSearchStore: ChatSearchPersisting {
    private let database: AppDatabase
    init(database: AppDatabase) { self.database = database }

    func createSession(scope: ChatSearchScope, visibilityRevision: UInt64, blockedAuthorIDs: Set<String>) async throws {
        try await database.dbPool.write { db in
            let identity = scope.identity
            // 세션 생성은 명시적 시작에서만 한다. 페이지/차단 갱신은 사라진 세션을 복원하지 않는다.
            try db.execute(sql: """
                INSERT INTO chatSearchSession(sessionID, accountID, accountEpoch, roomID, generation,
                    query, upperSeq, source, visibilityRevision, createdAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [identity.sessionID.uuidString, identity.accountID, identity.accountEpoch.uuidString,
                                  identity.roomID, String(identity.generation), scope.normalizedQuery, scope.upperSeq,
                                  ChatSearchSQL.source(scope.source), String(visibilityRevision), Date()])
            try self.insertBlockedAuthors(blockedAuthorIDs, sessionID: identity.sessionID.uuidString, in: db)
        }
    }

    func commitPage(identity: ChatSearchSessionIdentity, visibilityRevision: UInt64,
                    expectedCursor: ChatSearchCursor?, hits: [ChatSearchResultMetadata],
                    nextCursor: ChatSearchCursor?, isExhausted: Bool) async throws -> ChatSearchStoredState {
        guard hits.count <= 100, isExhausted || nextCursor != expectedCursor else { throw ChatSearchPersistenceError.invalidPage }
        return try await database.dbPool.write { db in
            let row = try ChatSearchSQL.session(identity, in: db)
            let before = try ChatSearchSQL.state(row, in: db)
            guard before.visibilityRevision == visibilityRevision else { throw ChatSearchPersistenceError.visibilityChanged }
            guard before.cursor == expectedCursor, !before.isExhausted else { throw ChatSearchPersistenceError.cursorChanged }
            let upper: Int64 = row["upperSeq"]
            var inserted = 0
            for hit in hits {
                guard !hit.messageID.isEmpty, !hit.senderUID.isEmpty, hit.seq > 0, hit.seq <= upper else {
                    throw ChatSearchPersistenceError.invalidPage
                }
                try db.execute(sql: """
                    INSERT OR IGNORE INTO chatSearchHit(sessionID, messageID, seq, senderUID)
                    SELECT ?, ?, ?, ?
                     WHERE NOT EXISTS(SELECT 1 FROM chatDeletedMessageMarker WHERE accountID = ? AND roomID = ? AND messageID = ?)
                       AND NOT EXISTS(SELECT 1 FROM chatSearchBlockedAuthor WHERE sessionID = ? AND senderUID = ?)
                    """, arguments: [identity.sessionID.uuidString, hit.messageID, hit.seq, hit.senderUID,
                                      identity.accountID, identity.roomID, hit.messageID, identity.sessionID.uuidString, hit.senderUID])
                inserted += db.changesCount
            }
            try db.execute(sql: "UPDATE chatSearchSession SET rawCursor = ?, isExhausted = ? WHERE sessionID = ?",
                           arguments: [nextCursor?.opaqueValue, isExhausted, identity.sessionID.uuidString])
            var state = try ChatSearchSQL.state(ChatSearchSQL.session(identity, in: db), in: db)
            state.insertedCount = inserted
            return state
        }
    }

    func applyVisibility(identity: ChatSearchSessionIdentity, revision: UInt64, blockedAuthorIDs: Set<String>) async throws -> ChatSearchStoredState {
        try await database.dbPool.write { db in
            let row = try ChatSearchSQL.session(identity, in: db)
            let before = try ChatSearchSQL.state(row, in: db)
            guard revision >= before.visibilityRevision else { throw ChatSearchPersistenceError.visibilityChanged }
            try self.insertBlockedAuthors(blockedAuthorIDs, sessionID: identity.sessionID.uuidString, in: db)
            try db.execute(sql: """
                DELETE FROM chatSearchHit WHERE sessionID = ? AND senderUID IN
                    (SELECT senderUID FROM chatSearchBlockedAuthor WHERE sessionID = ?)
                """, arguments: [identity.sessionID.uuidString, identity.sessionID.uuidString])
            try db.execute(sql: "UPDATE chatSearchSession SET visibilityRevision = ? WHERE sessionID = ?",
                           arguments: [String(revision), identity.sessionID.uuidString])
            return try ChatSearchSQL.state(ChatSearchSQL.session(identity, in: db), in: db)
        }
    }

    func state(identity: ChatSearchSessionIdentity) async throws -> ChatSearchStoredState {
        try await database.dbPool.read { db in
            try ChatSearchSQL.state(ChatSearchSQL.session(identity, in: db), in: db)
        }
    }

    func results(identity: ChatSearchSessionIdentity, offset: Int, limit: Int) async throws -> [ChatSearchResultMetadata] {
        guard offset >= 0, (1...100).contains(limit) else { throw ChatSearchPersistenceError.invalidPage }
        return try await database.dbPool.read { db in
            _ = try ChatSearchSQL.session(identity, in: db)
            return try Row.fetchAll(db, sql: """
                SELECT messageID, seq, senderUID FROM chatSearchHit WHERE sessionID = ?
                 ORDER BY seq DESC, messageID DESC LIMIT ? OFFSET ?
                """, arguments: [identity.sessionID.uuidString, limit, offset]).map {
                    ChatSearchResultMetadata(messageID: $0["messageID"], seq: $0["seq"], senderUID: $0["senderUID"])
                }
        }
    }

    func ordinal(identity: ChatSearchSessionIdentity, messageID: String) async throws -> Int? {
        try await database.dbPool.read { db in
            _ = try ChatSearchSQL.session(identity, in: db)
            guard let row = try Row.fetchOne(db, sql: "SELECT seq FROM chatSearchHit WHERE sessionID = ? AND messageID = ?",
                                            arguments: [identity.sessionID.uuidString, messageID]) else { return nil }
            let seq: Int64 = row["seq"]
            return try Int.fetchOne(db, sql: """
                SELECT COUNT(*) + 1 FROM chatSearchHit WHERE sessionID = ? AND (seq > ? OR (seq = ? AND messageID > ?))
                """, arguments: [identity.sessionID.uuidString, seq, seq, messageID])
        }
    }

    func closeSession(identity: ChatSearchSessionIdentity) async throws {
        try await database.dbPool.write { db in
            // stale 호출은 같은 ID라도 다른 epoch/generation의 세션을 지우지 못한다.
            try db.execute(sql: """
                DELETE FROM chatSearchSession WHERE sessionID = ? AND accountID = ? AND accountEpoch = ? AND roomID = ? AND generation = ?
                """, arguments: [identity.sessionID.uuidString, identity.accountID, identity.accountEpoch.uuidString,
                                  identity.roomID, String(identity.generation)])
        }
    }

    func neighbor(identity: ChatSearchSessionIdentity, anchor: ChatSearchResultMetadata, direction: ChatSearchDirection) async throws -> ChatSearchResultMetadata? {
        try await database.dbPool.read { db in
            _ = try ChatSearchSQL.session(identity, in: db)
            let comparison = direction == .older ? "<" : ">"
            let order = direction == .older ? "DESC" : "ASC"
            guard let row = try Row.fetchOne(db, sql: """
                SELECT messageID, seq, senderUID FROM chatSearchHit WHERE sessionID = ?
                 AND (seq \(comparison) ? OR (seq = ? AND messageID \(comparison) ?))
                 ORDER BY seq \(order), messageID \(order) LIMIT 1
                """, arguments: [identity.sessionID.uuidString, anchor.seq, anchor.seq, anchor.messageID]) else { return nil }
            return ChatSearchResultMetadata(messageID: row["messageID"], seq: row["seq"], senderUID: row["senderUID"])
        }
    }

    private func insertBlockedAuthors(_ authors: Set<String>, sessionID: String, in db: Database) throws {
        for author in authors {
            try db.execute(sql: "INSERT OR IGNORE INTO chatSearchBlockedAuthor(sessionID, senderUID) VALUES (?, ?)",
                           arguments: [sessionID, author])
        }
    }
}
