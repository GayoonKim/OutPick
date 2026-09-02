import GRDB
import Testing
@testable import OutPick

struct GRDBChatMessageStoreTests {
    @Test func saveAndPaginationPreserveAscendingResultOrder() async throws {
        let database = try TemporaryAppDatabase.make()
        let store = GRDBChatMessageStore(database: database)
        try await store.saveChatMessages((1...5).map { GRDBTestFixtures.message(id: "m\($0)", seq: Int64($0)) })

        let recent = try await store.fetchRecentMessages(inRoom: "room-1", limit: 3)
        let before = try await store.fetchMessagesBeforeSeq(inRoom: "room-1", beforeSeq: 4, limit: 2)
        let after = try await store.fetchMessagesAfterSeq(inRoom: "room-1", afterSeq: 3, limit: 2)

        #expect(recent.map(\.ID) == ["m3", "m4", "m5"])
        #expect(before.map(\.ID) == ["m2", "m3"])
        #expect(after.map(\.ID) == ["m4", "m5"])
    }

    @Test func ftsFailureRollsBackMessageAndMediaProjection() async throws {
        let database = try TemporaryAppDatabase.make()
        let store = GRDBChatMessageStore(database: database)
        let attachment = Attachment(type: .image, index: 0, pathThumb: "thumb", pathOriginal: "original", width: 10, height: 10, bytesOriginal: 1, hash: "hash", blurhash: nil, duration: nil)
        try await database.dbPool.write { db in
            try db.execute(sql: "DROP TABLE chatMessageFTS")
        }

        await #expect(throws: (any Error).self) {
            try await store.saveChatMessages([GRDBTestFixtures.message(id: "rollback", attachments: [attachment])])
        }

        let counts = try await database.dbPool.read { db in
            let messageCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM chatMessage WHERE id = 'rollback'") ?? -1
            let imageCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM imageIndex WHERE messageID = 'rollback'") ?? -1
            return (messageCount, imageCount)
        }
        #expect(counts.0 == 0)
        #expect(counts.1 == 0)
    }

    @Test func applyDeletionUpdatesMessageAndDeletesMediaInOneWrite() async throws {
        let database = try TemporaryAppDatabase.make()
        let store = GRDBChatMessageStore(database: database)
        let attachment = Attachment(type: .image, index: 0, pathThumb: "thumb", pathOriginal: "original", width: 10, height: 10, bytesOriginal: 1, hash: "hash", blurhash: nil, duration: nil)
        try await store.saveChatMessages([GRDBTestFixtures.message(id: "deleted", attachments: [attachment])])

        try await store.applyDeletion(messageIDs: ["deleted"], inRoom: "room-1")

        let message = try await store.fetchMessage(id: "deleted", inRoom: "room-1")
        #expect(message?.isDeleted == true)
        let imageCount = try await database.dbPool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM imageIndex WHERE messageID = 'deleted'") ?? -1
        }
        #expect(imageCount == 0)
    }

    @Test func roomRoleEventPersistsWithoutSearchOrMediaProjection() async throws {
        let database = try TemporaryAppDatabase.make()
        let store = GRDBChatMessageStore(database: database)
        let message = ChatMessage(
            ID: "role-event",
            seq: 3,
            roomID: "room-1",
            senderUID: "",
            senderNickname: "",
            messageType: .roomRoleEvent,
            serverGenerated: true,
            roleEvent: RoomRoleEventPayload(
                kind: .moderatorAssigned,
                subjectUID: "member-1",
                subjectNicknameSnapshot: "참여자"
            ),
            msg: nil,
            sentAt: nil,
            attachments: []
        )

        try await store.saveChatMessages([message])

        let stored = try await store.fetchMessage(id: message.ID, inRoom: message.roomID)
        let projectionCounts = try await database.dbPool.read { db in
            let fts = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM chatMessageFTS WHERE id = ?",
                arguments: [message.ID]
            ) ?? -1
            let media = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM imageIndex WHERE messageID = ?",
                arguments: [message.ID]
            ) ?? -1
            return (fts, media)
        }

        #expect(stored?.roleEvent == message.roleEvent)
        #expect(projectionCounts.0 == 0)
        #expect(projectionCounts.1 == 0)
    }
}
