import GRDB

enum ChatRoomCleanupSQL {
    static func deleteTransientRoomData(roomID: String, in db: Database) throws {
        try db.execute(sql: "DELETE FROM chatMessage WHERE roomID = ?", arguments: [roomID])
        try db.execute(sql: "DELETE FROM imageIndex WHERE roomID = ?", arguments: [roomID])
        try db.execute(sql: "DELETE FROM videoIndex WHERE roomID = ?", arguments: [roomID])
        try db.execute(sql: "DELETE FROM chatMessageFTS WHERE roomID = ?", arguments: [roomID])
    }

    static func deleteRoomDataAfterExit(roomID: String, currentUserID: String, in db: Database) throws {
        try deleteTransientRoomData(roomID: roomID, in: db)
        try db.execute(sql: "DELETE FROM chatOutgoingOutbox WHERE roomID = ?", arguments: [roomID])
        try db.execute(sql: "DELETE FROM RoomProfileDisplayCache WHERE roomID = ?", arguments: [roomID])
        try db.execute(sql: """
            DELETE FROM LocalChatUser
             WHERE userID != ?
               AND userID NOT IN (SELECT DISTINCT userID FROM RoomProfileDisplayCache)
        """, arguments: [currentUserID])
    }
}
