struct ChatPersistenceProvider {
    let messageStore: GRDBChatMessageStore
    let outboxStore: GRDBChatOutgoingOutboxStore
    let mediaStore: GRDBChatMediaIndexStore
    let profileStore: GRDBChatProfileCacheStore
    let roomLocalDataStore: GRDBChatRoomLocalDataStore
    let deletionSyncStore: GRDBChatDeletionSyncStore

    init(database: AppDatabase) {
        messageStore = GRDBChatMessageStore(database: database)
        outboxStore = GRDBChatOutgoingOutboxStore(database: database)
        mediaStore = GRDBChatMediaIndexStore(database: database)
        profileStore = GRDBChatProfileCacheStore(database: database)
        roomLocalDataStore = GRDBChatRoomLocalDataStore(database: database)
        deletionSyncStore = GRDBChatDeletionSyncStore(database: database)
    }
}
