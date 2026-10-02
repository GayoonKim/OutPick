import Foundation
import GRDB

enum ChatSearchSQL {
    static func createSchema(in db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE chatSearchSession (
                sessionID TEXT PRIMARY KEY NOT NULL,
                accountID TEXT NOT NULL, accountEpoch TEXT NOT NULL, roomID TEXT NOT NULL,
                generation TEXT NOT NULL, query TEXT NOT NULL, upperSeq INTEGER NOT NULL CHECK(upperSeq >= 0),
                source TEXT NOT NULL, rawCursor BLOB, isExhausted BOOLEAN NOT NULL DEFAULT 0,
                visibilityRevision TEXT NOT NULL, createdAt DATETIME NOT NULL
            );
            CREATE INDEX idx_chatSearchSession_room ON chatSearchSession(accountID, roomID);
            CREATE TABLE chatSearchHit (
                sessionID TEXT NOT NULL REFERENCES chatSearchSession(sessionID) ON DELETE CASCADE,
                messageID TEXT NOT NULL, seq INTEGER NOT NULL CHECK(seq > 0), senderUID TEXT NOT NULL,
                PRIMARY KEY(sessionID, messageID)
            );
            CREATE INDEX idx_chatSearchHit_order ON chatSearchHit(sessionID, seq DESC, messageID DESC);
            CREATE INDEX idx_chatSearchHit_author ON chatSearchHit(sessionID, senderUID);
            CREATE TABLE chatSearchBlockedAuthor (
                sessionID TEXT NOT NULL REFERENCES chatSearchSession(sessionID) ON DELETE CASCADE,
                senderUID TEXT NOT NULL, PRIMARY KEY(sessionID, senderUID)
            );
            """)
    }

    static func session(_ identity: ChatSearchSessionIdentity, in db: Database) throws -> Row {
        guard let row = try Row.fetchOne(db, sql: """
            SELECT * FROM chatSearchSession
             WHERE sessionID = ? AND accountID = ? AND accountEpoch = ? AND roomID = ? AND generation = ?
            """, arguments: [identity.sessionID.uuidString, identity.accountID, identity.accountEpoch.uuidString,
                              identity.roomID, String(identity.generation)]) else {
            throw ChatSearchPersistenceError.staleSession
        }
        return row
    }

    static func state(_ row: Row, in db: Database) throws -> ChatSearchStoredState {
        let id: String = row["sessionID"]
        let revision: String = row["visibilityRevision"]
        guard let parsed = UInt64(revision) else { throw ChatSearchPersistenceError.invalidPage }
        let cursor: Data? = row["rawCursor"]
        return ChatSearchStoredState(cursor: cursor.map { ChatSearchCursor(opaqueValue: $0) },
                                     isExhausted: row["isExhausted"], visibilityRevision: parsed,
                                     count: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM chatSearchHit WHERE sessionID = ?", arguments: [id]) ?? 0)
    }

    static func source(_ source: ChatMessageSearchSource) -> String {
        switch source {
        case .serverIndex: return "serverIndex"
        case .localOffline: return "localOffline"
        case .localFallbackAfterServerFailure: return "localFallbackAfterServerFailure"
        }
    }
}
