import Foundation
import GRDB

final class GRDBChatSearchLocalReader: ChatSearchLocalReading {
    private let database: AppDatabase
    init(database: AppDatabase) { self.database = database }
    func openSearchSnapshot(roomID: String) async throws -> any ChatSearchLocalSnapshot {
        // 별도 읽기 transaction이므로 도중 cache prune에도 동일한 검색 범위를 유지한다.
        try Reader(snapshot: database.dbPool.makeSnapshot(), roomID: roomID)
    }

    private final class Reader: ChatSearchLocalSnapshot {
        let snapshot: DatabaseSnapshot
        let roomID: String
        let id = UUID()
        struct Cursor: Codable { let snapshotID: UUID; let seq: Int64; let messageID: String }
        init(snapshot: DatabaseSnapshot, roomID: String) { self.snapshot = snapshot; self.roomID = roomID }
        func upperSequence() async throws -> Int64 {
            try await snapshot.read { db in
                try Int64.fetchOne(db, sql: "SELECT MAX(seq) FROM chatMessage WHERE roomID = ? AND seq > 0", arguments: [self.roomID]) ?? 0
            }
        }
        func page(upperSeq: Int64, after: ChatSearchCursor?, limit: Int) async throws -> ChatSearchCandidatePage {
            guard upperSeq >= 0, (1...100).contains(limit) else { throw ChatSearchFailure.invalidRequest }
            var cursor: Cursor?
            if let after {
                guard let parsed = try? JSONDecoder().decode(Cursor.self, from: after.opaqueValue), parsed.snapshotID == id else {
                    throw ChatSearchFailure.invalidRequest
                }
                cursor = parsed
            }
            let boundary = cursor
            let records = try await snapshot.read { db in
                var sql = "SELECT * FROM chatMessage WHERE roomID = ? AND seq > 0 AND seq <= ?"
                var args: [DatabaseValueConvertible] = [self.roomID, upperSeq]
                if let boundary {
                    sql += " AND (seq < ? OR (seq = ? AND id < ?))"
                    args += [boundary.seq, boundary.seq, boundary.messageID]
                }
                sql += " ORDER BY seq DESC, id DESC LIMIT ?"
                args.append(limit)
                return try ChatMessageRecord.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            }
            let messages = try records.map(ChatMessageRecordMapper.message)
            let next = try messages.last.map {
                ChatSearchCursor(opaqueValue: try JSONEncoder().encode(Cursor(snapshotID: id, seq: $0.seq, messageID: $0.ID)))
            } ?? after
            return ChatSearchCandidatePage(candidates: messages, nextCursor: next, isExhausted: records.count < limit)
        }
    }
}
