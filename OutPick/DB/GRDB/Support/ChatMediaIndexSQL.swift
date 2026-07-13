import Foundation
import GRDB

enum ChatMediaIndexSQL {
    static func replaceProjections(for message: ChatMessage, in db: Database) throws {
        try deleteProjections(messageID: message.ID, roomID: message.roomID, in: db)
        guard !message.isDeleted else { return }

        let sentAt = message.sentAt ?? Date()
        for attachment in message.attachments.sorted(by: { $0.index < $1.index }) {
            switch attachment.type {
            case .image:
                try db.execute(sql: """
                    INSERT OR REPLACE INTO imageIndex
                    (roomID, messageID, idx, thumbKey, originalKey, thumbURL, originalURL, width, height, bytesOriginal, hash, isFailed, localThumb, sentAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: projectionArguments(message: message, attachment: attachment, sentAt: sentAt))
            case .video:
                try db.execute(sql: """
                    INSERT OR REPLACE INTO videoIndex
                    (roomID, messageID, idx, thumbKey, originalKey, thumbURL, originalURL, width, height, bytesOriginal, duration, approxBitrateMbps, preset, hash, isFailed, localThumb, sentAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    message.roomID, message.ID, attachment.index,
                    cacheKey(attachment.hash), originalCacheKey(attachment.hash),
                    nonEmpty(attachment.pathThumb), nonEmpty(attachment.pathOriginal),
                    attachment.width, attachment.height, attachment.bytesOriginal,
                    attachment.duration, attachment.approxBitrateMbps, attachment.preset,
                    nonEmpty(attachment.hash), message.isFailed,
                    message.isFailed ? nonEmpty(attachment.pathThumb) : nil, sentAt
                ])
            }
        }
    }

    static func deleteProjections(messageID: String, roomID: String, in db: Database) throws {
        try db.execute(sql: "DELETE FROM imageIndex WHERE roomID = ? AND messageID = ?", arguments: [roomID, messageID])
        try db.execute(sql: "DELETE FROM videoIndex WHERE roomID = ? AND messageID = ?", arguments: [roomID, messageID])
    }

    static func deleteProjections(messageIDs: [String], roomID: String, in db: Database) throws {
        guard !messageIDs.isEmpty else { return }
        let placeholders = Array(repeating: "?", count: messageIDs.count).joined(separator: ",")
        let arguments = StatementArguments([roomID] + messageIDs)
        try db.execute(sql: "DELETE FROM imageIndex WHERE roomID = ? AND messageID IN (\(placeholders))", arguments: arguments)
        try db.execute(sql: "DELETE FROM videoIndex WHERE roomID = ? AND messageID IN (\(placeholders))", arguments: arguments)
    }

    private static func projectionArguments(
        message: ChatMessage,
        attachment: Attachment,
        sentAt: Date
    ) -> StatementArguments {
        StatementArguments([
            message.roomID, message.ID, attachment.index,
            cacheKey(attachment.hash), originalCacheKey(attachment.hash),
            nonEmpty(attachment.pathThumb), nonEmpty(attachment.pathOriginal),
            attachment.width, attachment.height, attachment.bytesOriginal,
            nonEmpty(attachment.hash), message.isFailed,
            message.isFailed ? nonEmpty(attachment.pathThumb) : nil, sentAt
        ] as [DatabaseValueConvertible?])
    }

    private static func cacheKey(_ hash: String) -> String? { nonEmpty(hash) }
    private static func originalCacheKey(_ hash: String) -> String? {
        guard !hash.isEmpty else { return nil }
        return hash + ":orig"
    }
    private static func nonEmpty(_ value: String) -> String? { value.isEmpty ? nil : value }
}
