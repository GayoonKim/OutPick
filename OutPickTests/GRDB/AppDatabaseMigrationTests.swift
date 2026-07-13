import GRDB
import Testing
@testable import OutPick

struct AppDatabaseMigrationTests {
    @Test func freshDatabaseAppliesFifteenMigrationsWithoutLegacyRoomImage() throws {
        let database = try TemporaryAppDatabase.make()

        try database.dbPool.read { db in
            let identifiers = try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid")
            #expect(identifiers == GRDBMigrationRegistry.identifiers)
            #expect(identifiers.count == 15)
            #expect(try db.tableExists("roomImage") == false)
            #expect(try db.tableExists("LocalChatUser"))
            #expect(try db.tableExists("RoomProfileDisplayCache"))
            #expect(try db.tableExists("chatMessage"))
            #expect(try db.tableExists("chatMessageFTS"))
            #expect(try db.tableExists("imageIndex"))
            #expect(try db.tableExists("videoIndex"))
            #expect(try db.tableExists("chatOutgoingOutbox"))
        }
    }

    @Test func senderUIDRebuilderRemovesLegacySenderIDAndBackfillsValidRows() throws {
        let queue = try DatabaseQueue()
        try queue.write { db in
            try db.create(table: "chatMessage") { table in
                table.column("id", .text).primaryKey()
                table.column("seq", .integer).notNull().defaults(to: 0)
                table.column("roomID", .text).notNull()
                table.column("senderID", .text).notNull()
                table.column("senderUID", .text)
                table.column("senderNickname", .text).notNull()
                table.column("msg", .text)
                table.column("attachments", .text)
                table.column("isFailed", .boolean).notNull().defaults(to: false)
                table.column("replyTo", .text)
            }
            try db.execute(sql: """
                INSERT INTO chatMessage
                (id, seq, roomID, senderID, senderUID, senderNickname, msg, attachments, isFailed)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: ["message-1", 12, "room-1", "legacy-sender", nil, "Legacy", "hello", "[]", false])

            try ChatMessageSenderUIDSchemaRebuilder.rebuildIfNeeded(in: db)
        }

        try queue.read { db in
            let columns = try db.columns(in: "chatMessage").map(\.name)
            #expect(columns.contains("senderUID"))
            #expect(!columns.contains("senderID"))
            let row = try Row.fetchOne(db, sql: "SELECT senderUID, seq FROM chatMessage WHERE id = ?", arguments: ["message-1"])
            #expect(row?["senderUID"] as String? == "legacy-sender")
            #expect(row?["seq"] as Int64? == 12)
        }
    }
}
