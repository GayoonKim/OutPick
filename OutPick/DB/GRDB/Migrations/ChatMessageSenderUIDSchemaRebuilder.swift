import GRDB

enum ChatMessageSenderUIDSchemaRebuilder {
    static func rebuildIfNeeded(in db: Database) throws {
        guard try db.tableExists("chatMessage") else { return }
        let columnNames = Set(try db.columns(in: "chatMessage").map(\.name))
        guard columnNames.contains("senderID") else { return }

        func expression(_ column: String, fallback: String = "NULL") -> String {
            columnNames.contains(column) ? column : fallback
        }

        let senderCandidates = [
            columnNames.contains("senderUID") ? "NULLIF(senderUID, '')" : nil,
            columnNames.contains("senderID") ? "NULLIF(senderID, '')" : nil
        ].compactMap { $0 }
        let senderExpression = "COALESCE(\(senderCandidates.joined(separator: ", ")), '')"

        try db.execute(sql: "DROP TABLE IF EXISTS chatMessage_senderUID_rebuild")
        try db.execute(sql: "ALTER TABLE chatMessage RENAME TO chatMessage_senderUID_rebuild")
        try GRDBMigrationRegistry.createCurrentChatMessageTable(in: db)

        try db.execute(sql: """
            INSERT OR REPLACE INTO chatMessage
            (id, seq, roomID, senderUID, senderEmail, senderNickname, senderAvatarPath, messageType, msg, sentAt, attachments, sharedContent, isFailed, replyPreview, isDeleted)
            SELECT
                id,
                COALESCE(\(expression("seq", fallback: "0")), 0),
                roomID,
                \(senderExpression),
                \(expression("senderEmail")),
                COALESCE(\(expression("senderNickname", fallback: "''")), ''),
                \(expression("senderAvatarPath")),
                \(expression("messageType")),
                \(expression("msg")),
                \(expression("sentAt")),
                COALESCE(\(expression("attachments", fallback: "'[]'")), '[]'),
                \(expression("sharedContent")),
                COALESCE(\(expression("isFailed", fallback: "0")), 0),
                \(expression("replyPreview", fallback: expression("replyTo"))),
                COALESCE(\(expression("isDeleted", fallback: "0")), 0)
              FROM chatMessage_senderUID_rebuild
             WHERE id IS NOT NULL
               AND roomID IS NOT NULL
               AND \(senderExpression) != ''
        """)

        try db.execute(sql: "DROP TABLE chatMessage_senderUID_rebuild")
        try GRDBMigrationRegistry.createChatMessageIndexes(in: db)
    }
}
