import Foundation
import GRDB

final class AppDatabase {
    let dbPool: DatabasePool

    static func live() throws -> AppDatabase {
        let databaseURL = try FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("OutPick.sqlite")
        return try AppDatabase(path: databaseURL.path)
    }

    init(path: String) throws {
        dbPool = try DatabasePool(path: path)
        try GRDBMigrationRegistry.migrate(dbPool)
    }

    init(dbPool: DatabasePool, migrate: Bool = true) throws {
        self.dbPool = dbPool
        if migrate {
            try GRDBMigrationRegistry.migrate(dbPool)
        }
    }

    func deleteAllUserSessionData() async throws {
        try await dbPool.write { db in
            try db.execute(sql: "DELETE FROM RoomProfileDisplayCache")
            try db.execute(sql: "DELETE FROM LocalChatUser")
            try db.execute(sql: "DELETE FROM chatOutgoingOutbox")
            try db.execute(sql: "DELETE FROM imageIndex")
            try db.execute(sql: "DELETE FROM videoIndex")
            try db.execute(sql: "DELETE FROM chatMessageFTS")
            try db.execute(sql: "DELETE FROM chatMessage")
        }
    }
}
