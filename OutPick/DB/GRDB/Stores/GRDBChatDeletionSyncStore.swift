import Foundation
import GRDB

protocol ChatDeletionSyncPersisting {
    func cursor(accountID: String, roomID: String) async throws -> Int64
    func hasServerMessages(roomID: String) async throws -> Bool
    func messageIDs(roomID: String) async throws -> [String]
    func apply(
        _ deltas: [ChatDeletionDelta],
        accountID: String,
        roomID: String
    ) async throws -> [ChatDeletionCleanupItem]
    func bootstrapCursor(_ revision: Int64, accountID: String, roomID: String) async throws
    func pendingCleanupItems() async throws -> [ChatDeletionCleanupItem]
    func completeCleanup(_ item: ChatDeletionCleanupItem) async throws
    func sanitize(_ messages: [ChatMessage], accountID: String, roomID: String) async throws -> [ChatMessage]
    func recordResolvedDeletions(
        _ deltas: [ChatDeletionDelta],
        accountID: String,
        roomID: String
    ) async throws -> [ChatDeletionCleanupItem]
}

final class GRDBChatDeletionSyncStore: ChatDeletionSyncPersisting {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func cursor(accountID: String, roomID: String) async throws -> Int64 {
        try await database.dbPool.read { db in
            try Int64.fetchOne(
                db,
                sql: "SELECT revision FROM chatDeletionCursor WHERE accountID = ? AND roomID = ?",
                arguments: [accountID, roomID]
            ) ?? 0
        }
    }

    func hasServerMessages(roomID: String) async throws -> Bool {
        try await database.dbPool.read { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM chatMessage WHERE roomID = ? AND seq > 0 LIMIT 1)",
                arguments: [roomID]
            ) ?? false
        }
    }

    func messageIDs(roomID: String) async throws -> [String] {
        try await database.dbPool.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT id FROM chatMessage WHERE roomID = ? AND seq > 0 ORDER BY seq ASC",
                arguments: [roomID]
            )
        }
    }

    func apply(
        _ deltas: [ChatDeletionDelta],
        accountID: String,
        roomID: String
    ) async throws -> [ChatDeletionCleanupItem] {
        guard !deltas.isEmpty else { return [] }
        return try await database.dbPool.write { db in
            let current = try Int64.fetchOne(
                db,
                sql: "SELECT revision FROM chatDeletionCursor WHERE accountID = ? AND roomID = ?",
                arguments: [accountID, roomID]
            ) ?? 0
            let pending = deltas
                .filter { $0.revision > current }
                .sorted { $0.revision < $1.revision }
            guard !pending.isEmpty else { return [] }

            var expected = current + 1
            var cleanup = Set<CleanupKey>()
            for delta in pending {
                guard delta.roomID == roomID, delta.revision == expected else {
                    throw ChatDeletionSyncError.revisionGap(expected: expected, actual: delta.revision)
                }
                try collectCleanup(messageID: delta.messageID, roomID: roomID, db: db, into: &cleanup)
                try scrubMessage(delta, roomID: roomID, db: db)
                try scrubReplyPreviews(messageID: delta.messageID, roomID: roomID, db: db, into: &cleanup)
                try upsertMarker(delta, accountID: accountID, roomID: roomID, db: db)
                expected += 1
            }

            for item in cleanup {
                try db.execute(
                    sql: "INSERT OR IGNORE INTO chatDeletionCleanup(kind, path, createdAt) VALUES (?, ?, ?)",
                    arguments: [item.kind.rawValue, item.path, Date()]
                )
            }
            let revision = expected - 1
            try db.execute(sql: """
                INSERT INTO chatDeletionCursor(accountID, roomID, revision) VALUES (?, ?, ?)
                ON CONFLICT(accountID, roomID) DO UPDATE SET revision = excluded.revision
            """, arguments: [accountID, roomID, revision])
            return cleanup.map { ChatDeletionCleanupItem(kind: $0.kind, path: $0.path) }
        }
    }

    func bootstrapCursor(_ revision: Int64, accountID: String, roomID: String) async throws {
        guard revision >= 0 else { throw ChatDeletionSyncError.invalidHead }
        try await database.dbPool.write { db in
            try db.execute(sql: """
                INSERT INTO chatDeletionCursor(accountID, roomID, revision) VALUES (?, ?, ?)
                ON CONFLICT(accountID, roomID) DO UPDATE SET revision = MAX(revision, excluded.revision)
            """, arguments: [accountID, roomID, revision])
        }
    }

    func pendingCleanupItems() async throws -> [ChatDeletionCleanupItem] {
        try await database.dbPool.read { db in
            try Row.fetchAll(db, sql: "SELECT kind, path FROM chatDeletionCleanup ORDER BY createdAt ASC").compactMap { row in
                guard let kind = ChatDeletionCleanupItem.Kind(rawValue: row["kind"]),
                      let path: String = row["path"] else { return nil }
                return ChatDeletionCleanupItem(kind: kind, path: path)
            }
        }
    }

    func completeCleanup(_ item: ChatDeletionCleanupItem) async throws {
        try await database.dbPool.write { db in
            try db.execute(
                sql: "DELETE FROM chatDeletionCleanup WHERE kind = ? AND path = ?",
                arguments: [item.kind.rawValue, item.path]
            )
        }
    }

    func recordResolvedDeletions(
        _ deltas: [ChatDeletionDelta],
        accountID: String,
        roomID: String
    ) async throws -> [ChatDeletionCleanupItem] {
        guard !deltas.isEmpty else { return [] }
        return try await database.dbPool.write { db in
            var cleanup = Set<CleanupKey>()
            for delta in deltas where delta.roomID == roomID {
                try collectCleanup(messageID: delta.messageID, roomID: roomID, db: db, into: &cleanup)
                try scrubMessage(delta, roomID: roomID, db: db)
                try scrubReplyPreviews(
                    messageID: delta.messageID,
                    roomID: roomID,
                    db: db,
                    into: &cleanup
                )
                try upsertMarker(delta, accountID: accountID, roomID: roomID, db: db)
            }
            for item in cleanup {
                try db.execute(
                    sql: "INSERT OR IGNORE INTO chatDeletionCleanup(kind, path, createdAt) VALUES (?, ?, ?)",
                    arguments: [item.kind.rawValue, item.path, Date()]
                )
            }
            return cleanup.map { ChatDeletionCleanupItem(kind: $0.kind, path: $0.path) }
        }
    }

    func sanitize(
        _ messages: [ChatMessage],
        accountID: String,
        roomID: String
    ) async throws -> [ChatMessage] {
        try await database.dbPool.read { db in
            try Self.sanitize(messages, accountID: accountID, roomID: roomID, db: db)
        }
    }

    /// 저장 transaction에서도 같은 marker 정책을 사용해 검증/저장 사이의 삭제 경합을 막는다.
    static func sanitize(
        _ messages: [ChatMessage], accountID: String, roomID: String, db: Database
    ) throws -> [ChatMessage] {
        guard !messages.isEmpty else { return [] }
        let candidateIDs = Set(
            messages.map(\.ID) + messages.compactMap { $0.replyPreview?.messageID }
        )
        guard !candidateIDs.isEmpty else { return messages }
        let ids = Array(candidateIDs)
        let markers: [String: Marker] = try {
            let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
            var arguments: [DatabaseValueConvertible] = [accountID, roomID]
            arguments.append(contentsOf: ids)
            let rows = try Row.fetchAll(db, sql: """
                SELECT messageID, seq, revision, deletedAt, anonymizesSender
                  FROM chatDeletedMessageMarker
                 WHERE accountID = ? AND roomID = ?
                   AND messageID IN (\(placeholders))
            """, arguments: StatementArguments(arguments))
            return Dictionary(uniqueKeysWithValues: rows.map { row in
                let marker = Marker(
                    seq: row["seq"],
                    revision: row["revision"],
                    deletedAt: row["deletedAt"],
                    anonymizesSender: row["anonymizesSender"]
                )
                return (row["messageID"] as String, marker)
            })
        }()

        return messages.map { message in
            if let marker = markers[message.ID] {
                return ChatMessage(
                    ID: message.ID,
                    seq: marker.seq > 0 ? marker.seq : message.seq,
                    unreadMessageSeq: message.unreadMessageSeq,
                    roomID: roomID,
                    senderUID: marker.anonymizesSender ? "" : message.senderUID,
                    senderNickname: marker.anonymizesSender ? "알 수 없는 사용자" : message.senderNickname,
                    senderAvatarPath: marker.anonymizesSender ? nil : message.senderAvatarPath,
                    messageType: nil,
                    msg: nil,
                    sentAt: message.sentAt,
                    attachments: [],
                    sharedContent: nil,
                    replyPreview: marker.anonymizesSender ? nil : message.replyPreview,
                    isFailed: false,
                    isDeleted: true,
                    deletionRevision: marker.revision,
                    deletedAt: marker.deletedAt
                )
            }

            guard let preview = message.replyPreview,
                  markers[preview.messageID] != nil else { return message }
            var sanitized = message
            sanitized.replyPreview = ReplyPreview(
                messageID: preview.messageID,
                sender: "",
                text: "",
                imagesCount: 0,
                videosCount: 0,
                firstThumbPath: nil,
                senderAvatarPath: nil,
                sentAt: nil,
                isDeleted: true
            )
            return sanitized
        }
    }

    private struct CleanupKey: Hashable {
        let kind: ChatDeletionCleanupItem.Kind
        let path: String
    }

    private struct Marker {
        let seq: Int64
        let revision: Int64
        let deletedAt: Date?
        let anonymizesSender: Bool
    }

    private func collectCleanup(
        messageID: String,
        roomID: String,
        db: Database,
        into cleanup: inout Set<CleanupKey>
    ) throws {
        guard let attachmentsJSON = try String.fetchOne(
            db,
            sql: "SELECT attachments FROM chatMessage WHERE roomID = ? AND id = ?",
            arguments: [roomID, messageID]
        ), let data = attachmentsJSON.data(using: .utf8),
              let attachments = try? JSONDecoder().decode([Attachment].self, from: data) else { return }

        for attachment in attachments {
            append(path: attachment.thumbResourcePath, kind: .image, into: &cleanup)
            append(
                path: attachment.originalResourcePath,
                kind: attachment.type == .video ? .video : .image,
                into: &cleanup
            )
        }
    }

    private func upsertMarker(
        _ delta: ChatDeletionDelta,
        accountID: String,
        roomID: String,
        db: Database
    ) throws {
        try db.execute(sql: """
            INSERT INTO chatDeletedMessageMarker(
                accountID, roomID, messageID, seq, revision, deletedAt, anonymizesSender
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(accountID, roomID, messageID) DO UPDATE SET
                seq = excluded.seq,
                anonymizesSender = CASE
                    WHEN excluded.revision >= revision THEN excluded.anonymizesSender
                    ELSE anonymizesSender
                END,
                revision = MAX(revision, excluded.revision),
                deletedAt = COALESCE(excluded.deletedAt, deletedAt)
        """, arguments: [
            accountID, roomID, delta.messageID, delta.seq,
            delta.revision, delta.deletedAt, delta.anonymizesSender,
        ])
    }

    private func scrubMessage(_ delta: ChatDeletionDelta, roomID: String, db: Database) throws {
        if delta.anonymizesSender {
            try db.execute(sql: """
                UPDATE chatMessage
                   SET senderUID = NULL,
                       senderNickname = '알 수 없는 사용자',
                       senderAvatarPath = NULL,
                       messageType = NULL,
                       msg = NULL,
                       attachments = '[]',
                       sharedContent = NULL,
                       isFailed = 0,
                       replyPreview = NULL,
                       isDeleted = 1,
                       deletionRevision = ?,
                       deletedAt = ?
                 WHERE roomID = ? AND id = ?
            """, arguments: [delta.revision, delta.deletedAt, roomID, delta.messageID])
        } else {
            try db.execute(sql: """
                UPDATE chatMessage
                   SET messageType = NULL,
                       msg = NULL,
                       attachments = '[]',
                       sharedContent = NULL,
                       isFailed = 0,
                       isDeleted = 1,
                       deletionRevision = ?,
                       deletedAt = ?
                 WHERE roomID = ? AND id = ?
            """, arguments: [delta.revision, delta.deletedAt, roomID, delta.messageID])
        }
        try db.execute(
            sql: "DELETE FROM chatMessageFTS WHERE roomID = ? AND id = ?",
            arguments: [roomID, delta.messageID]
        )
        try db.execute(
            sql: "DELETE FROM chatOutgoingOutbox WHERE roomID = ? AND messageID = ?",
            arguments: [roomID, delta.messageID]
        )
        try ChatMediaIndexSQL.deleteProjections(messageID: delta.messageID, roomID: roomID, in: db)
    }

    private func scrubReplyPreviews(
        messageID: String,
        roomID: String,
        db: Database,
        into cleanup: inout Set<CleanupKey>
    ) throws {
        let rows = try Row.fetchAll(db, sql: """
            SELECT id, replyPreview FROM chatMessage
             WHERE roomID = ? AND replyPreview IS NOT NULL
               AND json_extract(replyPreview, '$.messageID') = ?
        """, arguments: [roomID, messageID])
        let minimal = "{\"messageID\":\"\(escapedJSONString(messageID))\",\"sender\":\"\",\"text\":\"\",\"imagesCount\":0,\"videosCount\":0,\"isDeleted\":true}"
        for row in rows {
            if let raw: String = row["replyPreview"],
               let preview = ChatMessageRecordMapper.decode(ReplyPreview.self, from: raw),
               let path = preview.firstThumbPath {
                append(path: path, kind: .image, into: &cleanup)
            }
            let id: String = row["id"]
            try db.execute(
                sql: "UPDATE chatMessage SET replyPreview = ? WHERE roomID = ? AND id = ?",
                arguments: [minimal, roomID, id]
            )
        }
    }

    private func append(
        path: String,
        kind: ChatDeletionCleanupItem.Kind,
        into cleanup: inout Set<CleanupKey>
    ) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let resolvedKind: ChatDeletionCleanupItem.Kind =
            (trimmed.hasPrefix("/") || trimmed.hasPrefix("file://")) ? .localFile : kind
        cleanup.insert(CleanupKey(kind: resolvedKind, path: trimmed))
    }

    private func escapedJSONString(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
