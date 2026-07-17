import GRDB

final class GRDBChatOutgoingOutboxStore: ChatOutgoingOutboxPersisting {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func saveOutgoingOutboxRecord(_ record: ChatOutgoingOutboxRecord) async throws {
        try await database.dbPool.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO chatOutgoingOutbox
                (messageID, roomID, kind, stage, createdAt, updatedAt, localPayloadJSON, uploadedPayloadJSON, lastError)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                record.messageID, record.roomID, record.kind.rawValue, record.stage.rawValue,
                record.createdAt, record.updatedAt, record.localPayloadJSON,
                record.uploadedPayloadJSON, record.lastError
            ])
        }
    }

    func fetchOutgoingOutboxRecord(messageID: String) async throws -> ChatOutgoingOutboxRecord? {
        try await database.dbPool.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM chatOutgoingOutbox WHERE messageID = ? LIMIT 1", arguments: [messageID]) else { return nil }
            return ChatOutgoingOutboxRecord(
                messageID: row["messageID"], roomID: row["roomID"],
                kind: ChatOutgoingOutboxKind(rawValue: row["kind"] as String) ?? .text,
                stage: ChatOutgoingOutboxStage(rawValue: row["stage"] as String) ?? .failed,
                createdAt: row["createdAt"], updatedAt: row["updatedAt"],
                localPayloadJSON: row["localPayloadJSON"], uploadedPayloadJSON: row["uploadedPayloadJSON"],
                lastError: row["lastError"]
            )
        }
    }

    func fetchOutgoingOutboxRecords(messageIDs: [String]) async throws -> [ChatOutgoingOutboxRecord] {
        guard !messageIDs.isEmpty else { return [] }
        return try await database.dbPool.read { db in
            let placeholders = Array(repeating: "?", count: messageIDs.count).joined(separator: ",")
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM chatOutgoingOutbox WHERE messageID IN (\(placeholders))",
                arguments: StatementArguments(messageIDs)
            )
            return rows.map { row in
                ChatOutgoingOutboxRecord(
                    messageID: row["messageID"], roomID: row["roomID"],
                    kind: ChatOutgoingOutboxKind(rawValue: row["kind"] as String) ?? .text,
                    stage: ChatOutgoingOutboxStage(rawValue: row["stage"] as String) ?? .failed,
                    createdAt: row["createdAt"], updatedAt: row["updatedAt"],
                    localPayloadJSON: row["localPayloadJSON"], uploadedPayloadJSON: row["uploadedPayloadJSON"],
                    lastError: row["lastError"]
                )
            }
        }
    }

    func deleteOutgoingOutboxRecord(messageID: String) async throws {
        try await database.dbPool.write { db in
            try db.execute(sql: "DELETE FROM chatOutgoingOutbox WHERE messageID = ?", arguments: [messageID])
        }
    }

    func deleteOutgoingOutboxRecords(messageIDs: [String]) async throws {
        guard !messageIDs.isEmpty else { return }
        try await database.dbPool.write { db in
            let placeholders = Array(repeating: "?", count: messageIDs.count).joined(separator: ",")
            try db.execute(
                sql: "DELETE FROM chatOutgoingOutbox WHERE messageID IN (\(placeholders))",
                arguments: StatementArguments(messageIDs)
            )
        }
    }
}
