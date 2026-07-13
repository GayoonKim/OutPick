import Foundation
import GRDB

final class GRDBChatProfileCacheStore: ChatProfileCachePersisting {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    @discardableResult
    func upsertLocalChatUser(userID: String, nickname: String, profileImagePath: String?) throws -> LocalChatUser {
        let user = LocalChatUser(userID: userID, nickname: nickname, profileImagePath: profileImagePath)
        try database.dbPool.write { db in
            try ChatProfileRecordMapper.record(from: user).insert(db, onConflict: .replace)
        }
        return user
    }

    func fetchLocalChatUser(userID: String) throws -> LocalChatUser? {
        try database.dbPool.read { db in
            try LocalChatUserRecord.fetchOne(db, key: userID).map(ChatProfileRecordMapper.model)
        }
    }

    func upsertRoomProfileDisplayCache(
        roomID: String,
        userID: String,
        lastSeenAt: Date,
        lastMessageSeq: Int?,
        lastMessageID: String?,
        updatedAt: Date,
        maxEntriesPerRoom: Int
    ) throws {
        guard maxEntriesPerRoom > 0 else { return }
        try database.dbPool.write { db in
            try LocalChatUserRecord(userID: userID, nickname: "", profileImagePath: nil).insert(db, onConflict: .ignore)
            try RoomProfileDisplayCacheRecord(
                roomID: roomID, userID: userID, lastSeenAt: lastSeenAt,
                lastMessageSeq: lastMessageSeq, lastMessageID: lastMessageID, updatedAt: updatedAt
            ).insert(db, onConflict: .replace)
            try db.execute(sql: """
                DELETE FROM RoomProfileDisplayCache
                 WHERE roomID = ?
                   AND userID NOT IN (
                        SELECT userID FROM RoomProfileDisplayCache
                         WHERE roomID = ?
                         ORDER BY lastSeenAt DESC, COALESCE(lastMessageSeq, -1) DESC, userID COLLATE NOCASE ASC
                         LIMIT ?
                   )
            """, arguments: [roomID, roomID, maxEntriesPerRoom])
        }
    }

    func fetchRoomProfileDisplayCacheUserIDs(roomID: String) throws -> [String] {
        try database.dbPool.read { db in
            try String.fetchAll(db, sql: """
                SELECT userID FROM RoomProfileDisplayCache WHERE roomID = ?
                 ORDER BY lastSeenAt DESC, COALESCE(lastMessageSeq, -1) DESC, userID COLLATE NOCASE ASC
            """, arguments: [roomID])
        }
    }

    func countRoomProfileDisplayCache(roomID: String) throws -> Int {
        try database.dbPool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM RoomProfileDisplayCache WHERE roomID = ?", arguments: [roomID]) ?? 0
        }
    }
}
