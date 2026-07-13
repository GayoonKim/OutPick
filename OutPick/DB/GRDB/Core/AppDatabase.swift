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
}
