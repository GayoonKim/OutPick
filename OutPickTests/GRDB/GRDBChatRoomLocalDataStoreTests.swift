import Foundation
import GRDB
import Testing
@testable import OutPick

struct GRDBChatRoomLocalDataStoreTests {
    @Test func transientCleanupKeepsOutboxAndProfileCache() async throws {
        let database = try TemporaryAppDatabase.make()
        let messageStore = GRDBChatMessageStore(database: database)
        let outboxStore = GRDBChatOutgoingOutboxStore(database: database)
        let profileStore = GRDBChatProfileCacheStore(database: database)
        let cleanupStore = GRDBChatRoomLocalDataStore(database: database)
        try await seedRoom(messageStore: messageStore, outboxStore: outboxStore, profileStore: profileStore)

        try cleanupStore.cleanTransientRoomData(roomID: "room-1")

        #expect(try await messageStore.fetchMessage(id: "message-1", inRoom: "room-1") == nil)
        #expect(try await outboxStore.fetchOutgoingOutboxRecord(messageID: "message-1") != nil)
        #expect(try profileStore.countRoomProfileDisplayCache(roomID: "room-1") == 1)
    }

    @Test func exitCleanupDeletesOutboxAndPrunesOnlyOrphanUsers() async throws {
        let database = try TemporaryAppDatabase.make()
        let messageStore = GRDBChatMessageStore(database: database)
        let outboxStore = GRDBChatOutgoingOutboxStore(database: database)
        let profileStore = GRDBChatProfileCacheStore(database: database)
        let cleanupStore = GRDBChatRoomLocalDataStore(database: database)
        try await seedRoom(messageStore: messageStore, outboxStore: outboxStore, profileStore: profileStore)
        try profileStore.upsertLocalChatUser(userID: "current-user", nickname: "Me", profileImagePath: nil)
        try profileStore.upsertLocalChatUser(userID: "other-user", nickname: "Other", profileImagePath: nil)
        try profileStore.upsertRoomProfileDisplayCache(
            roomID: "room-2", userID: "other-user", lastSeenAt: Date(),
            lastMessageSeq: 1, lastMessageID: "other-message", updatedAt: Date(), maxEntriesPerRoom: 20
        )

        try cleanupStore.cleanRoomDataAfterExit(roomID: "room-1", currentUserID: "current-user")

        #expect(try await outboxStore.fetchOutgoingOutboxRecord(messageID: "message-1") == nil)
        #expect(try profileStore.fetchLocalChatUser(userID: "user-1") == nil)
        #expect(try profileStore.fetchLocalChatUser(userID: "other-user") != nil)
        #expect(try profileStore.fetchLocalChatUser(userID: "current-user") != nil)
    }

    @Test func exitCleanupFailureRollsBackAllRoomDeletes() async throws {
        let database = try TemporaryAppDatabase.make()
        let messageStore = GRDBChatMessageStore(database: database)
        let outboxStore = GRDBChatOutgoingOutboxStore(database: database)
        let profileStore = GRDBChatProfileCacheStore(database: database)
        let cleanupStore = GRDBChatRoomLocalDataStore(database: database)
        try await seedRoom(messageStore: messageStore, outboxStore: outboxStore, profileStore: profileStore)
        try await database.dbPool.write { db in
            try db.execute(sql: """
                CREATE TRIGGER fail_room_profile_delete
                BEFORE DELETE ON RoomProfileDisplayCache
                BEGIN
                    SELECT RAISE(ABORT, 'forced cleanup failure');
                END
            """)
        }

        #expect(throws: (any Error).self) {
            try cleanupStore.cleanRoomDataAfterExit(roomID: "room-1", currentUserID: "current-user")
        }

        #expect(try await messageStore.fetchMessage(id: "message-1", inRoom: "room-1") != nil)
        #expect(try await outboxStore.fetchOutgoingOutboxRecord(messageID: "message-1") != nil)
        #expect(try profileStore.countRoomProfileDisplayCache(roomID: "room-1") == 1)
    }

    private func seedRoom(
        messageStore: GRDBChatMessageStore,
        outboxStore: GRDBChatOutgoingOutboxStore,
        profileStore: GRDBChatProfileCacheStore
    ) async throws {
        try await messageStore.saveChatMessages([GRDBTestFixtures.message(id: "message-1")])
        try await outboxStore.saveOutgoingOutboxRecord(ChatOutgoingOutboxRecord(
            messageID: "message-1", roomID: "room-1", kind: .text, stage: .failed,
            createdAt: Date(), updatedAt: Date(), localPayloadJSON: nil,
            uploadedPayloadJSON: nil, lastError: nil
        ))
        try profileStore.upsertLocalChatUser(userID: "user-1", nickname: "User", profileImagePath: nil)
        try profileStore.upsertRoomProfileDisplayCache(
            roomID: "room-1", userID: "user-1", lastSeenAt: Date(),
            lastMessageSeq: 1, lastMessageID: "message-1", updatedAt: Date(), maxEntriesPerRoom: 20
        )
    }
}
