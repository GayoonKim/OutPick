import GRDB

enum GRDBMigrationRegistry {
    static let identifiers = [
        "foreignKeysOn",
        "createLocalChatUser",
        "createRoomProfileDisplayCache",
        "createChatMessage",
        "addSeqToChatMessage",
        "migrateChatMessageSenderUID",
        "createChatMessageFTS",
        "addReplyPreviewToChatMessage",
        "addIsDeletedToChatMessage",
        "addSenderAvatarPathToChatMessage",
        "addLookbookShareToChatMessage",
        "rebuildChatMessageSenderUIDSchema",
        "createImageIndex",
        "createVideoIndex",
        "createChatOutgoingOutbox"
    ]

    static func migrate(_ writer: some DatabaseWriter) throws {
        var migrator = makeMigrator()
        try migrator.migrate(writer)
    }

    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("foreignKeysOn") { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON;")
        }
        migrator.registerMigration("createLocalChatUser") { db in
            try db.create(table: "LocalChatUser", options: [.ifNotExists]) { table in
                table.column("userID", .text).primaryKey()
                table.column("nickname", .text).notNull()
                table.column("profileImagePath", .text)
            }
            try db.create(index: "idx_LocalChatUser_nickname", on: "LocalChatUser", columns: ["nickname"], ifNotExists: true)
        }
        migrator.registerMigration("createRoomProfileDisplayCache") { db in
            try createRoomProfileDisplayCacheTable(in: db)
        }
        migrator.registerMigration("createChatMessage") { db in
            try db.create(table: "chatMessage") { table in
                table.column("id", .text).primaryKey()
                table.column("seq", .integer).notNull().defaults(to: 0)
                table.column("roomID", .text).notNull()
                table.column("senderUID", .text).notNull()
                table.column("senderEmail", .text)
                table.column("senderNickname", .text).notNull()
                table.column("senderAvatarPath", .text)
                table.column("msg", .text)
                table.column("sentAt", .datetime)
                table.column("attachments", .text)
                table.column("isFailed", .boolean).notNull().defaults(to: false)
                table.column("replyTo", .text)
            }
            try createChatMessageIndexes(in: db)
        }
        migrator.registerMigration("addSeqToChatMessage") { db in
            try addColumnIfMissing("seq", to: "chatMessage", in: db) { table in
                table.add(column: "seq", .integer).notNull().defaults(to: 0)
            }
            try db.create(index: "idx_chatMessage_roomID_seq", on: "chatMessage", columns: ["roomID", "seq"], ifNotExists: true)
        }
        migrator.registerMigration("migrateChatMessageSenderUID") { db in
            try addColumnIfMissing("senderUID", to: "chatMessage", in: db) { $0.add(column: "senderUID", .text) }
            try addColumnIfMissing("senderEmail", to: "chatMessage", in: db) { $0.add(column: "senderEmail", .text) }
            let columns = Set(try db.columns(in: "chatMessage").map(\.name))
            if columns.contains("senderID") {
                try db.execute(sql: """
                    UPDATE chatMessage
                       SET senderUID = COALESCE(NULLIF(senderUID, ''), senderID)
                     WHERE senderUID IS NULL OR senderUID = ''
                """)
            }
        }
        migrator.registerMigration("createChatMessageFTS") { db in
            try db.create(virtualTable: "chatMessageFTS", using: FTS5()) { table in
                table.column("msg")
                table.column("roomID")
                table.column("id").notIndexed()
            }
        }
        migrator.registerMigration("addReplyPreviewToChatMessage") { db in
            try addColumnIfMissing("replyPreview", to: "chatMessage", in: db) { $0.add(column: "replyPreview", .text) }
        }
        migrator.registerMigration("addIsDeletedToChatMessage") { db in
            try addColumnIfMissing("isDeleted", to: "chatMessage", in: db) {
                $0.add(column: "isDeleted", .boolean).notNull().defaults(to: false)
            }
        }
        migrator.registerMigration("addSenderAvatarPathToChatMessage") { db in
            try addColumnIfMissing("senderAvatarPath", to: "chatMessage", in: db) { $0.add(column: "senderAvatarPath", .text) }
        }
        migrator.registerMigration("addLookbookShareToChatMessage") { db in
            try addColumnIfMissing("messageType", to: "chatMessage", in: db) { $0.add(column: "messageType", .text) }
            try addColumnIfMissing("sharedContent", to: "chatMessage", in: db) { $0.add(column: "sharedContent", .text) }
        }
        migrator.registerMigration("rebuildChatMessageSenderUIDSchema") { db in
            try ChatMessageSenderUIDSchemaRebuilder.rebuildIfNeeded(in: db)
        }
        migrator.registerMigration("createImageIndex") { db in
            try createImageIndexTable(in: db)
        }
        migrator.registerMigration("createVideoIndex") { db in
            try createVideoIndexTable(in: db)
        }
        migrator.registerMigration("createChatOutgoingOutbox") { db in
            try db.create(table: "chatOutgoingOutbox", options: [.ifNotExists]) { table in
                table.column("messageID", .text).primaryKey()
                table.column("roomID", .text).notNull()
                table.column("kind", .text).notNull()
                table.column("stage", .text).notNull()
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
                table.column("localPayloadJSON", .text)
                table.column("uploadedPayloadJSON", .text)
                table.column("lastError", .text)
            }
            try db.create(index: "idx_chatOutgoingOutbox_room_updated", on: "chatOutgoingOutbox", columns: ["roomID", "updatedAt"], ifNotExists: true)
        }

        return migrator
    }

    static func createCurrentChatMessageTable(in db: Database) throws {
        try db.create(table: "chatMessage") { table in
            table.column("id", .text).primaryKey()
            table.column("seq", .integer).notNull().defaults(to: 0)
            table.column("roomID", .text).notNull()
            table.column("senderUID", .text).notNull()
            table.column("senderEmail", .text)
            table.column("senderNickname", .text).notNull()
            table.column("senderAvatarPath", .text)
            table.column("messageType", .text)
            table.column("msg", .text)
            table.column("sentAt", .datetime)
            table.column("attachments", .text)
            table.column("sharedContent", .text)
            table.column("isFailed", .boolean).notNull().defaults(to: false)
            table.column("replyPreview", .text)
            table.column("isDeleted", .boolean).notNull().defaults(to: false)
        }
    }

    static func createChatMessageIndexes(in db: Database) throws {
        try db.create(index: "idx_chatMessage_roomID_sentAt", on: "chatMessage", columns: ["roomID", "sentAt"], ifNotExists: true)
        try db.create(index: "idx_chatMessage_roomID_seq", on: "chatMessage", columns: ["roomID", "seq"], ifNotExists: true)
    }

    private static func createRoomProfileDisplayCacheTable(in db: Database) throws {
        try db.create(table: "RoomProfileDisplayCache", options: [.ifNotExists]) { table in
            table.column("roomID", .text).notNull()
            table.column("userID", .text).notNull().references("LocalChatUser", column: "userID", onDelete: .cascade)
            table.column("lastSeenAt", .datetime).notNull()
            table.column("lastMessageSeq", .integer)
            table.column("lastMessageID", .text)
            table.column("updatedAt", .datetime).notNull()
            table.primaryKey(["roomID", "userID"])
        }
        try db.create(index: "idx_RoomProfileDisplayCache_room", on: "RoomProfileDisplayCache", columns: ["roomID"], ifNotExists: true)
        try db.create(index: "idx_RoomProfileDisplayCache_room_lru", on: "RoomProfileDisplayCache", columns: ["roomID", "lastSeenAt", "lastMessageSeq", "userID"], ifNotExists: true)
        try db.create(index: "idx_RoomProfileDisplayCache_user", on: "RoomProfileDisplayCache", columns: ["userID"], ifNotExists: true)
    }

    private static func createImageIndexTable(in db: Database) throws {
        try db.create(table: "imageIndex") { table in
            addCommonMediaColumns(to: table)
            table.primaryKey(["roomID", "messageID", "idx"])
        }
        try db.create(index: "idx_imageIndex_room_sentAt", on: "imageIndex", columns: ["roomID", "sentAt"], ifNotExists: true)
        try db.create(index: "idx_imageIndex_messageID", on: "imageIndex", columns: ["messageID"], ifNotExists: true)
    }

    private static func createVideoIndexTable(in db: Database) throws {
        try db.create(table: "videoIndex") { table in
            addCommonMediaColumns(to: table, includeSentAt: false)
            table.column("duration", .double)
            table.column("approxBitrateMbps", .double)
            table.column("preset", .text)
            table.column("sentAt", .datetime).notNull()
            table.primaryKey(["roomID", "messageID", "idx"])
        }
        try db.create(index: "idx_videoIndex_room_sentAt", on: "videoIndex", columns: ["roomID", "sentAt"], ifNotExists: true)
        try db.create(index: "idx_videoIndex_messageID", on: "videoIndex", columns: ["messageID"], ifNotExists: true)
    }

    private static func addCommonMediaColumns(to table: TableDefinition, includeSentAt: Bool = true) {
        table.column("roomID", .text).notNull()
        table.column("messageID", .text).notNull()
        table.column("idx", .integer).notNull()
        table.column("thumbKey", .text)
        table.column("originalKey", .text)
        table.column("thumbURL", .text)
        table.column("originalURL", .text)
        table.column("width", .integer)
        table.column("height", .integer)
        table.column("bytesOriginal", .integer)
        table.column("hash", .text)
        table.column("isFailed", .boolean).notNull().defaults(to: false)
        table.column("localThumb", .text)
        if includeSentAt {
            table.column("sentAt", .datetime).notNull()
        }
    }

    private static func addColumnIfMissing(
        _ column: String,
        to table: String,
        in db: Database,
        change: (TableAlteration) -> Void
    ) throws {
        guard !Set(try db.columns(in: table).map(\.name)).contains(column) else { return }
        try db.alter(table: table, body: change)
    }
}
