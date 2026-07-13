final class GRDBChatRoomLocalDataStore: ChatRoomLocalDataPersisting {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func cleanTransientRoomData(roomID: String) throws {
        try database.dbPool.write { db in
            try ChatRoomCleanupSQL.deleteTransientRoomData(roomID: roomID, in: db)
        }
    }

    func cleanRoomDataAfterExit(roomID: String, currentUserID: String) throws {
        try database.dbPool.write { db in
            try ChatRoomCleanupSQL.deleteRoomDataAfterExit(roomID: roomID, currentUserID: currentUserID, in: db)
        }
    }
}
