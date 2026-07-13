import Foundation
import GRDB

final class GRDBChatMessageStore: ChatMessagePersisting, ChatMessageSearching {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func saveChatMessages(_ messages: [ChatMessage]) async throws {
        guard !messages.isEmpty else { return }
        try await database.dbPool.write { db in
            for message in messages {
                guard let record = ChatMessageRecordMapper.record(from: message) else { continue }
                try record.insert(db, onConflict: .replace)
                try db.execute(
                    sql: "INSERT OR REPLACE INTO chatMessageFTS(id, msg, roomID) VALUES (?, ?, ?)",
                    arguments: [message.ID, message.msg ?? "", message.roomID]
                )
                try ChatMediaIndexSQL.replaceProjections(for: message, in: db)
            }
        }

        if let roomID = messages.last?.roomID,
           try countMessages(inRoom: roomID) > 3_300 {
            try pruneMessages(inRoom: roomID, keepLast: 3_000)
        }
    }

    func fetchMessage(id messageID: String, inRoom roomID: String) async throws -> ChatMessage? {
        try await database.dbPool.read { db in
            try ChatMessageRecord.fetchOne(db, sql: "SELECT * FROM chatMessage WHERE roomID = ? AND id = ? LIMIT 1", arguments: [roomID, messageID])
                .map { try ChatMessageRecordMapper.message(from: $0) }
        }
    }

    func fetchFailedOutgoingMessages(inRoom roomID: String, senderUID: String) async throws -> [ChatMessage] {
        try await database.dbPool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT chatMessage.*,
                       chatOutgoingOutbox.kind AS outboxKind,
                       chatOutgoingOutbox.localPayloadJSON AS outboxLocalPayloadJSON,
                       chatOutgoingOutbox.uploadedPayloadJSON AS outboxUploadedPayloadJSON
                  FROM chatMessage
                  LEFT JOIN chatOutgoingOutbox ON chatOutgoingOutbox.messageID = chatMessage.id
                 WHERE chatMessage.roomID = ?
                   AND chatMessage.senderUID = ?
                   AND chatMessage.isFailed = 1
                   AND chatMessage.isDeleted = 0
                 ORDER BY chatMessage.sentAt ASC, chatMessage.id ASC
            """, arguments: [roomID, senderUID])

            return try rows.map { row in
                let record = try ChatMessageRecord(row: row)
                var message = try ChatMessageRecordMapper.message(from: record)
                message.attachments = self.stableFailedOutgoingAttachments(from: row, fallback: message.attachments)
                return message
            }
        }
    }

    func hardDeleteMessage(id messageID: String, inRoom roomID: String) async throws {
        try await database.dbPool.write { db in
            try ChatMediaIndexSQL.deleteProjections(messageID: messageID, roomID: roomID, in: db)
            try db.execute(sql: "DELETE FROM chatMessageFTS WHERE roomID = ? AND id = ?", arguments: [roomID, messageID])
            try db.execute(sql: "DELETE FROM chatMessage WHERE roomID = ? AND id = ?", arguments: [roomID, messageID])
        }
    }

    func applyDeletion(messageIDs: [String], inRoom roomID: String) async throws {
        guard !messageIDs.isEmpty else { return }
        try await database.dbPool.write { db in
            let placeholders = Array(repeating: "?", count: messageIDs.count).joined(separator: ",")
            var updateArguments: [DatabaseValueConvertible] = [true, roomID]
            updateArguments.append(contentsOf: messageIDs)
            try db.execute(
                sql: "UPDATE chatMessage SET isDeleted = ? WHERE roomID = ? AND id IN (\(placeholders))",
                arguments: StatementArguments(updateArguments)
            )

            var replyArguments: [DatabaseValueConvertible] = [1, roomID]
            replyArguments.append(contentsOf: messageIDs)
            try db.execute(sql: """
                UPDATE chatMessage
                   SET replyPreview = json_set(replyPreview, '$.isDeleted', ?)
                 WHERE roomID = ?
                   AND replyPreview IS NOT NULL
                   AND json_extract(replyPreview, '$.messageID') IN (\(placeholders))
            """, arguments: StatementArguments(replyArguments))
            try ChatMediaIndexSQL.deleteProjections(messageIDs: messageIDs, roomID: roomID, in: db)
        }
    }

    func fetchRecentMessages(inRoom roomID: String, limit: Int) async throws -> [ChatMessage] {
        let records = try await fetchRecords(
            sql: "SELECT * FROM chatMessage WHERE roomID = ? ORDER BY seq DESC, id DESC LIMIT ?",
            arguments: [roomID, limit]
        )
        return try records.reversed().map(ChatMessageRecordMapper.message)
    }

    func fetchMessagesAfterSeq(inRoom roomID: String, afterSeq: Int64, limit: Int) async throws -> [ChatMessage] {
        try await messages(sql: "SELECT * FROM chatMessage WHERE roomID = ? AND seq > ? ORDER BY seq ASC, id ASC LIMIT ?", arguments: [roomID, afterSeq, limit])
    }

    func fetchMessagesBeforeSeq(inRoom roomID: String, beforeSeq: Int64, limit: Int) async throws -> [ChatMessage] {
        let records = try await fetchRecords(sql: "SELECT * FROM chatMessage WHERE roomID = ? AND seq < ? ORDER BY seq DESC, id DESC LIMIT ?", arguments: [roomID, beforeSeq, limit])
        return try records.reversed().map(ChatMessageRecordMapper.message)
    }

    func fetchOlderMessages(inRoom roomID: String, before anchorMessageID: String, limit: Int) async throws -> [ChatMessage] {
        try await database.dbPool.read { db in
            guard let anchorSeq = try Int64.fetchOne(db, sql: "SELECT seq FROM chatMessage WHERE roomID = ? AND id = ? LIMIT 1", arguments: [roomID, anchorMessageID]) else { return [] }
            let records = try ChatMessageRecord.fetchAll(db, sql: "SELECT * FROM chatMessage WHERE roomID = ? AND seq < ? ORDER BY seq DESC, id DESC LIMIT ?", arguments: [roomID, anchorSeq, limit])
            return try records.reversed().map(ChatMessageRecordMapper.message)
        }
    }

    func fetchNewerMessages(inRoom roomID: String, after anchorMessageID: String, limit: Int) async throws -> [ChatMessage] {
        try await database.dbPool.read { db in
            guard let anchorSeq = try Int64.fetchOne(db, sql: "SELECT seq FROM chatMessage WHERE roomID = ? AND id = ? LIMIT 1", arguments: [roomID, anchorMessageID]) else { return [] }
            let records = try ChatMessageRecord.fetchAll(db, sql: "SELECT * FROM chatMessage WHERE roomID = ? AND seq > ? ORDER BY seq ASC, id ASC LIMIT ?", arguments: [roomID, anchorSeq, limit])
            return try records.map(ChatMessageRecordMapper.message)
        }
    }

    func fetchMessages(in roomID: String, containing keyword: String?) async throws -> [ChatMessage] {
        if let keyword, !keyword.isEmpty {
            return try await messages(
                sql: "SELECT * FROM chatMessage WHERE roomID = ? AND msg LIKE ? ORDER BY seq ASC, id ASC",
                arguments: [roomID, "%\(keyword)%"]
            )
        }
        return try await messages(sql: "SELECT * FROM chatMessage WHERE roomID = ? ORDER BY seq ASC, id ASC", arguments: [roomID])
    }

    private func countMessages(inRoom roomID: String) throws -> Int {
        try database.dbPool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM chatMessage WHERE roomID = ?", arguments: [roomID]) ?? 0
        }
    }

    private func pruneMessages(inRoom roomID: String, keepLast count: Int, batchSize: Int = 500) throws {
        try database.dbPool.write { db in
            let totalCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM chatMessage WHERE roomID = ?", arguments: [roomID]) ?? 0
            guard totalCount > count else { return }
            let records = try String.fetchAll(db, sql: "SELECT id FROM chatMessage WHERE roomID = ? ORDER BY seq ASC, id ASC LIMIT ?", arguments: [roomID, min(totalCount - count, batchSize)])
            guard !records.isEmpty else { return }
            let placeholders = Array(repeating: "?", count: records.count).joined(separator: ",")
            try ChatMediaIndexSQL.deleteProjections(messageIDs: records, roomID: roomID, in: db)
            try db.execute(sql: "DELETE FROM chatMessageFTS WHERE id IN (\(placeholders))", arguments: StatementArguments(records))
            try db.execute(sql: "DELETE FROM chatMessage WHERE id IN (\(placeholders))", arguments: StatementArguments(records))
        }
    }

    private func fetchRecords(sql: String, arguments: StatementArguments) async throws -> [ChatMessageRecord] {
        try await database.dbPool.read { db in
            try ChatMessageRecord.fetchAll(db, sql: sql, arguments: arguments)
        }
    }

    private func messages(sql: String, arguments: StatementArguments) async throws -> [ChatMessage] {
        try await fetchRecords(sql: sql, arguments: arguments).map(ChatMessageRecordMapper.message)
    }

    private func stableFailedOutgoingAttachments(from row: Row, fallback: [Attachment]) -> [Attachment] {
        guard let rawKind = row["outboxKind"] as? String,
              let kind = ChatOutgoingOutboxKind(rawValue: rawKind) else { return fallback }
        switch kind {
        case .text:
            return fallback
        case .images:
            if let uploaded = ChatMessageRecordMapper.decode(ChatOutgoingOutboxUploadedImagesPayload.self, from: row["outboxUploadedPayloadJSON"] as? String), !uploaded.attachments.isEmpty {
                return uploaded.attachments
            }
            guard let local = ChatMessageRecordMapper.decode(ChatOutgoingOutboxImagePayload.self, from: row["outboxLocalPayloadJSON"] as? String) else { return fallback }
            return local.items.sorted(by: { $0.index < $1.index }).map { item in
                Attachment(type: .image, index: item.index,
                           pathThumb: currentOutboxDisplayPath(from: item.thumbFilePath),
                           pathOriginal: currentOutboxDisplayPath(from: item.originalFilePath),
                           width: item.originalWidth, height: item.originalHeight,
                           bytesOriginal: item.bytesOriginal, hash: item.sha256,
                           blurhash: nil, duration: nil)
            }
        case .video:
            if let uploaded = ChatMessageRecordMapper.decode(VideoMetaPayload.self, from: row["outboxUploadedPayloadJSON"] as? String) {
                return [Attachment(type: .video, index: 0, pathThumb: uploaded.thumbnailPath,
                                   pathOriginal: uploaded.storagePath, width: uploaded.width, height: uploaded.height,
                                   bytesOriginal: Int(uploaded.sizeBytes), hash: uploaded.messageID,
                                   blurhash: nil, duration: uploaded.duration,
                                   approxBitrateMbps: uploaded.approxBitrateMbps, preset: uploaded.preset)]
            }
            guard let local = ChatMessageRecordMapper.decode(ChatOutgoingOutboxVideoPayload.self, from: row["outboxLocalPayloadJSON"] as? String) else { return fallback }
            return [Attachment(type: .video, index: 0,
                               pathThumb: currentOutboxDisplayPath(from: local.thumbnailFilePath),
                               pathOriginal: currentOutboxDisplayPath(from: local.compressedFilePath),
                               width: local.width, height: local.height, bytesOriginal: Int(local.sizeBytes),
                               hash: local.sha256, blurhash: nil, duration: local.duration,
                               approxBitrateMbps: local.approxBitrateMbps, preset: local.preset)]
        }
    }

    private func currentOutboxDisplayPath(from storedPath: String) -> String {
        let trimmed = storedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let root = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("ChatOutgoingOutbox", isDirectory: true) else { return storedPath }
        if trimmed.hasPrefix("file://"), let url = URL(string: trimmed), url.isFileURL {
            return FileManager.default.fileExists(atPath: url.path) ? url.path : migratedOutboxPath(from: url.path, root: root) ?? storedPath
        }
        if trimmed.hasPrefix("/") {
            return FileManager.default.fileExists(atPath: trimmed) ? trimmed : migratedOutboxPath(from: trimmed, root: root) ?? storedPath
        }
        return root.appendingPathComponent(trimmed).path
    }

    private func migratedOutboxPath(from path: String, root: URL) -> String? {
        guard let range = path.range(of: "ChatOutgoingOutbox/") else { return nil }
        let resolved = root.appendingPathComponent(String(path[range.upperBound...]))
        return FileManager.default.fileExists(atPath: resolved.path) ? resolved.path : nil
    }
}
