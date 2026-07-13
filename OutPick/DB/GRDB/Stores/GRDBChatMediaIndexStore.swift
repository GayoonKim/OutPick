import Foundation
import GRDB

final class GRDBChatMediaIndexStore: ChatMediaIndexPersisting {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func countImageIndex(inRoom roomID: String) throws -> Int {
        try count(table: "imageIndex", roomID: roomID)
    }

    func countVideoIndex(inRoom roomID: String) throws -> Int {
        try count(table: "videoIndex", roomID: roomID)
    }

    func fetchLatestImageIndex(inRoom roomID: String, limit: Int) throws -> [ImageIndexMeta] {
        try database.dbPool.read { db in
            try ImageIndexRecord.fetchAll(db, sql: "SELECT * FROM imageIndex WHERE roomID = ? ORDER BY sentAt DESC, messageID DESC, idx ASC LIMIT ?", arguments: [roomID, limit])
                .map(ChatMediaIndexRecordMapper.model)
        }
    }

    func fetchLatestVideoIndex(inRoom roomID: String, limit: Int) throws -> [VideoIndexMeta] {
        try database.dbPool.read { db in
            try VideoIndexRecord.fetchAll(db, sql: "SELECT * FROM videoIndex WHERE roomID = ? ORDER BY sentAt DESC, messageID DESC, idx ASC LIMIT ?", arguments: [roomID, limit])
                .map(ChatMediaIndexRecordMapper.model)
        }
    }

    func fetchOlderImageIndex(inRoom roomID: String, beforeSentAt: Date, beforeMessageID: String, limit: Int) throws -> [ImageIndexMeta] {
        try database.dbPool.read { db in
            try ImageIndexRecord.fetchAll(db, sql: """
                SELECT * FROM imageIndex
                 WHERE roomID = ? AND (sentAt < ? OR (sentAt = ? AND messageID < ?))
                 ORDER BY sentAt DESC, messageID DESC, idx ASC LIMIT ?
            """, arguments: [roomID, beforeSentAt, beforeSentAt, beforeMessageID, limit])
            .map(ChatMediaIndexRecordMapper.model)
        }
    }

    func fetchOlderVideoIndex(inRoom roomID: String, beforeSentAt: Date, beforeMessageID: String, limit: Int) throws -> [VideoIndexMeta] {
        try database.dbPool.read { db in
            try VideoIndexRecord.fetchAll(db, sql: """
                SELECT * FROM videoIndex
                 WHERE roomID = ? AND (sentAt < ? OR (sentAt = ? AND messageID < ?))
                 ORDER BY sentAt DESC, messageID DESC, idx ASC LIMIT ?
            """, arguments: [roomID, beforeSentAt, beforeSentAt, beforeMessageID, limit])
            .map(ChatMediaIndexRecordMapper.model)
        }
    }

    func upsertMediaIndexEntries(_ entries: [ChatRoomMediaIndexEntry]) throws {
        guard !entries.isEmpty else { return }
        try database.dbPool.write { db in
            for entry in entries {
                switch entry.type {
                case .image:
                    try db.execute(sql: """
                        INSERT OR REPLACE INTO imageIndex
                        (roomID, messageID, idx, thumbKey, originalKey, thumbURL, originalURL, width, height, bytesOriginal, hash, isFailed, localThumb, sentAt)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [entry.roomID, entry.messageID, entry.idx, entry.thumbKey, entry.originalKey,
                                      entry.thumbURL, entry.originalURL, entry.width, entry.height, entry.bytesOriginal,
                                      entry.hash, false, nil, entry.sentAt])
                case .video:
                    try db.execute(sql: """
                        INSERT OR REPLACE INTO videoIndex
                        (roomID, messageID, idx, thumbKey, originalKey, thumbURL, originalURL, width, height, bytesOriginal, duration, approxBitrateMbps, preset, hash, isFailed, localThumb, sentAt)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [entry.roomID, entry.messageID, entry.idx, entry.thumbKey, entry.originalKey,
                                      entry.thumbURL, entry.originalURL, entry.width, entry.height, entry.bytesOriginal,
                                      entry.duration, nil, nil, entry.hash, false, nil, entry.sentAt])
                }
            }
        }
    }

    func deleteImageIndexRow(forMessageID messageID: String, idx: Int, inRoom roomID: String?) throws {
        try deleteRow(table: "imageIndex", messageID: messageID, idx: idx, roomID: roomID)
    }

    func deleteVideoIndexRow(forMessageID messageID: String, idx: Int, inRoom roomID: String?) throws {
        try deleteRow(table: "videoIndex", messageID: messageID, idx: idx, roomID: roomID)
    }

    func updateVideoDuration(inRoom roomID: String, messageID: String, idx: Int, duration: Double) throws {
        try database.dbPool.write { db in
            try db.execute(sql: "UPDATE videoIndex SET duration = COALESCE(duration, ?) WHERE roomID = ? AND messageID = ? AND idx = ?", arguments: [duration, roomID, messageID, idx])
        }
    }

    private func count(table: String, roomID: String) throws -> Int {
        try database.dbPool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table) WHERE roomID = ?", arguments: [roomID]) ?? 0
        }
    }

    private func deleteRow(table: String, messageID: String, idx: Int, roomID: String?) throws {
        try database.dbPool.write { db in
            if let roomID {
                try db.execute(sql: "DELETE FROM \(table) WHERE roomID = ? AND messageID = ? AND idx = ?", arguments: [roomID, messageID, idx])
            } else {
                try db.execute(sql: "DELETE FROM \(table) WHERE messageID = ? AND idx = ?", arguments: [messageID, idx])
            }
        }
    }
}
