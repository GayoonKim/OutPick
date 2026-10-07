import Foundation
import GRDB

struct GRDBLookbookImportRequestStore: LookbookImportRequestStoringRepositoryProtocol {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func prepareOrReuse(_ request: LookbookImportRequest) async throws -> (request: LookbookImportRequest, didReuse: Bool) {
        _ = try await deleteExpiredSettled(now: Self.currentTimestamp(), limit: 100)
        return try await database.dbPool.write { db in
            if let row = try LookbookImportRequestRecord.fetchOne(
                db,
                sql: """
                    SELECT * FROM lookbookImportRequest
                     WHERE ownerUID = ? AND kind = ?
                       AND payloadDigest = ?
                       AND (brandID IS ? OR (kind = 'createBrand' AND ? IS NULL))
                       AND (
                           localState IN ('prepared', 'submitting', 'accepted', 'needsReconcile')
                           OR (kind = 'createBrand' AND localState = 'settled' AND expiresAt > ?)
                       )
                     ORDER BY createdAt DESC LIMIT 1
                """,
                arguments: [
                    request.ownerUID, request.kind, request.payloadDigest,
                    request.brandID, request.brandID, Self.currentTimestamp()
                ]
            ), let domain = row.domain {
                return (domain, true)
            }
            try LookbookImportRequestRecord(request).insert(db)
            return (request, false)
        }
    }

    func update(_ request: LookbookImportRequest) async throws {
        try await database.dbPool.write { db in
            guard try LookbookImportRequestRecord.fetchOne(
                db,
                key: ["ownerUID": request.ownerUID, "requestID": request.requestID]
            ) != nil else { throw LookbookImportRequestStoreError.missingRequest }
            try db.execute(
                sql: """
                    UPDATE lookbookImportRequest
                       SET brandID = ?, localState = ?, batchID = ?, receiptJSON = ?, stateRevision = ?,
                           updatedAt = ?, settledAt = ?, expiresAt = ?
                     WHERE ownerUID = ? AND requestID = ?
                """,
                arguments: [
                    request.brandID, request.localState.rawValue, request.batchID, request.receiptJSON,
                    request.stateRevision, request.updatedAt, request.settledAt,
                    request.expiresAt, request.ownerUID, request.requestID
                ]
            )
        }
    }

    func fetchUnsettled(ownerUID: String, brandID: String?) async throws -> [LookbookImportRequest] {
        _ = try await deleteExpiredSettled(now: Self.currentTimestamp(), limit: 100)
        return try await database.dbPool.read { db in
            let rows = try LookbookImportRequestRecord.fetchAll(
                db,
                sql: """
                    SELECT * FROM lookbookImportRequest
                     WHERE ownerUID = ? AND localState != 'settled'
                       AND (? IS NULL OR brandID = ?)
                     ORDER BY createdAt DESC
                """,
                arguments: [ownerUID, brandID, brandID]
            )
            return rows.compactMap(\.domain)
        }
    }

    func deleteExpiredSettled(now: Int64, limit: Int) async throws -> Int {
        guard limit > 0 else { return 0 }
        return try await database.dbPool.write { db in
            try db.execute(
                sql: """
                    DELETE FROM lookbookImportRequest
                     WHERE rowid IN (
                         SELECT rowid FROM lookbookImportRequest
                          WHERE localState = 'settled' AND expiresAt <= ?
                          ORDER BY expiresAt LIMIT ?
                     )
                """,
                arguments: [now, min(limit, 500)]
            )
            return db.changesCount
        }
    }

    private static func currentTimestamp() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down))
    }
}

enum LookbookImportRequestStoreError: Error {
    case missingRequest
}
