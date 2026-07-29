import Foundation
import GRDB
import Testing
@testable import OutPick

struct AccountDeletionLocalDataCleanupTests {
    @Test
    func deletesEveryUserScopedGRDBTable() async throws {
        let database = try TemporaryAppDatabase.make()
        let tables = [
            "RoomProfileDisplayCache",
            "LocalChatUser",
            "chatOutgoingOutbox",
            "imageIndex",
            "videoIndex",
            "chatMessageFTS",
            "chatMessage"
        ]
        try await database.dbPool.write { db in
            try db.execute(
                sql: "INSERT INTO LocalChatUser (userID, nickname) VALUES (?, ?)",
                arguments: ["user-1", "아웃피커"]
            )
            try db.execute(
                sql: """
                    INSERT INTO RoomProfileDisplayCache
                    (roomID, userID, lastSeenAt, updatedAt)
                    VALUES (?, ?, ?, ?)
                """,
                arguments: ["room-1", "user-1", Date(), Date()]
            )
            try db.execute(
                sql: """
                    INSERT INTO chatMessage
                    (id, seq, roomID, senderUID, senderNickname, isFailed, isDeleted)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: ["message-1", 1, "room-1", "user-1", "아웃피커", false, false]
            )
            try db.execute(
                sql: "INSERT INTO chatMessageFTS (msg, roomID, id) VALUES (?, ?, ?)",
                arguments: ["메시지", "room-1", "message-1"]
            )
            try db.execute(
                sql: """
                    INSERT INTO imageIndex
                    (roomID, messageID, idx, isFailed, sentAt)
                    VALUES (?, ?, ?, ?, ?)
                """,
                arguments: ["room-1", "message-1", 0, false, Date()]
            )
            try db.execute(
                sql: """
                    INSERT INTO videoIndex
                    (roomID, messageID, idx, isFailed, sentAt)
                    VALUES (?, ?, ?, ?, ?)
                """,
                arguments: ["room-1", "message-1", 0, false, Date()]
            )
            try db.execute(
                sql: """
                    INSERT INTO chatOutgoingOutbox
                    (messageID, roomID, kind, stage, createdAt, updatedAt)
                    VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: ["message-1", "room-1", "text", "pending", Date(), Date()]
            )
        }

        try await database.deleteAllUserSessionData()

        let counts = try await database.dbPool.read { db in
            try tables.map { table in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? -1
            }
        }
        #expect(counts == Array(repeating: 0, count: tables.count))
    }
}
