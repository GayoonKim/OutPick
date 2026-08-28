import Foundation
import GRDB
import Testing
@testable import OutPick

struct GRDBChatDeletionSyncStoreTests {
    @Test func emptyLocalBootstrapAdvancesToHeadWithoutHistoricalDeltaQuery() async throws {
        let database = try TemporaryAppDatabase.make()
        let deletionStore = GRDBChatDeletionSyncStore(database: database)
        let repository = StubChatDeletionSyncRepository(
            head: 42,
            deltas: [ChatDeletionDelta(
                messageID: "historical",
                roomID: "room-1",
                seq: 1,
                revision: 1,
                deletedAt: nil
            )]
        )
        let useCase = ChatDeletionSyncUseCase(
            repository: repository,
            persistence: deletionStore,
            mediaCleaner: NoopChatDeletionMediaCleaner()
        )

        let applied = try await useCase.reconcile(
            roomID: "room-1",
            accountID: "account-1",
            allowEmptyLocalBootstrap: true
        )

        #expect(applied.isEmpty)
        #expect(try await deletionStore.cursor(accountID: "account-1", roomID: "room-1") == 42)
        #expect(await repository.pageRequestCount() == 0)
    }

    @Test func existingLocalMessagesApplyMultipleDeltaPagesToHead() async throws {
        let database = try TemporaryAppDatabase.make()
        let messageStore = GRDBChatMessageStore(database: database)
        let deletionStore = GRDBChatDeletionSyncStore(database: database)
        try await messageStore.saveChatMessages((1...3).map {
            GRDBTestFixtures.message(id: "m\($0)", seq: Int64($0))
        })
        let repository = StubChatDeletionSyncRepository(
            head: 3,
            deltas: (1...3).map {
                ChatDeletionDelta(
                    messageID: "m\($0)",
                    roomID: "room-1",
                    seq: Int64($0),
                    revision: Int64($0),
                    deletedAt: nil
                )
            }
        )
        let useCase = ChatDeletionSyncUseCase(
            repository: repository,
            persistence: deletionStore,
            mediaCleaner: NoopChatDeletionMediaCleaner(),
            pageSize: 2
        )

        let applied = try await useCase.reconcile(
            roomID: "room-1",
            accountID: "account-1",
            allowEmptyLocalBootstrap: true
        )

        #expect(applied == ["m1", "m2", "m3"])
        #expect(try await deletionStore.cursor(accountID: "account-1", roomID: "room-1") == 3)
        #expect(await repository.pageRequestCount() == 2)
    }

    @Test func applyScrubsMessageReplySearchMediaAndOutboxAtomically() async throws {
        let database = try TemporaryAppDatabase.make()
        let messageStore = GRDBChatMessageStore(database: database)
        let deletionStore = GRDBChatDeletionSyncStore(database: database)
        let attachment = Attachment(
            type: .image,
            index: 0,
            pathThumb: "thumb/path",
            pathOriginal: "original/path",
            width: 10,
            height: 10,
            bytesOriginal: 10,
            hash: "hash"
        )
        let target = GRDBTestFixtures.message(
            id: "target",
            seq: 1,
            text: "오늘 8시에 강남역에서 만나자",
            attachments: [attachment],
            replyPreview: ReplyPreview(
                messageID: "source",
                sender: "Earlier User",
                text: "이전 메시지"
            )
        )
        let reply = ChatMessage(
            ID: "reply",
            seq: 2,
            roomID: "room-1",
            senderUID: "user-2",
            senderNickname: "Reply User",
            senderAvatarPath: nil,
            messageType: .text,
            msg: "좋아요",
            sentAt: Date(timeIntervalSince1970: 2),
            attachments: [],
            replyPreview: ReplyPreview(
                messageID: "target",
                sender: "User",
                text: target.msg ?? "",
                imagesCount: 1,
                firstThumbPath: "thumb/path",
                sentAt: target.sentAt
            )
        )
        try await messageStore.saveChatMessages([target, reply])
        try await database.dbPool.write { db in
            try db.execute(sql: """
                INSERT INTO chatOutgoingOutbox(
                    messageID, roomID, kind, stage, createdAt, updatedAt, localPayloadJSON
                ) VALUES ('target', 'room-1', 'image', 'failed', ?, ?, '{}')
            """, arguments: [Date(), Date()])
        }

        let cleanup = try await deletionStore.apply(
            [ChatDeletionDelta(
                messageID: "target",
                roomID: "room-1",
                seq: 1,
                revision: 1,
                deletedAt: Date(timeIntervalSince1970: 10)
            )],
            accountID: "account-1",
            roomID: "room-1"
        )

        let scrubbedTarget = try #require(await messageStore.fetchMessage(id: "target", inRoom: "room-1"))
        let scrubbedReply = try #require(await messageStore.fetchMessage(id: "reply", inRoom: "room-1"))
        #expect(scrubbedTarget.isDeleted)
        #expect(scrubbedTarget.senderUID == target.senderUID)
        #expect(scrubbedTarget.senderNickname == target.senderNickname)
        #expect(scrubbedTarget.sentAt == target.sentAt)
        #expect(scrubbedTarget.replyPreview == target.replyPreview)
        #expect(scrubbedTarget.msg == nil)
        #expect(scrubbedTarget.attachments.isEmpty)
        #expect(scrubbedTarget.deletionRevision == 1)
        #expect(scrubbedReply.replyPreview?.isDeleted == true)
        #expect(scrubbedReply.replyPreview?.sender.isEmpty == true)
        #expect(scrubbedReply.replyPreview?.text.isEmpty == true)
        #expect(try await deletionStore.cursor(accountID: "account-1", roomID: "room-1") == 1)
        #expect(Set(cleanup.map(\.path)) == ["thumb/path", "original/path"])

        let counts = try await database.dbPool.read { db in
            let fts = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM chatMessageFTS WHERE id = 'target'") ?? -1
            let media = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM imageIndex WHERE messageID = 'target'") ?? -1
            let outbox = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM chatOutgoingOutbox WHERE messageID = 'target'") ?? -1
            return (fts, media, outbox)
        }
        #expect(counts.0 == 0)
        #expect(counts.1 == 0)
        #expect(counts.2 == 0)
    }

    @Test func accountDeletionAnonymizesSenderButKeepsMessageTime() async throws {
        let database = try TemporaryAppDatabase.make()
        let messageStore = GRDBChatMessageStore(database: database)
        let deletionStore = GRDBChatDeletionSyncStore(database: database)
        let target = GRDBTestFixtures.message(id: "target", seq: 1)
        try await messageStore.saveChatMessages([target])

        _ = try await deletionStore.apply(
            [ChatDeletionDelta(
                messageID: "target",
                roomID: "room-1",
                seq: 1,
                revision: 1,
                deletedAt: Date(timeIntervalSince1970: 10),
                anonymizesSender: true
            )],
            accountID: "account-1",
            roomID: "room-1"
        )

        let scrubbed = try #require(await messageStore.fetchMessage(id: "target", inRoom: "room-1"))
        #expect(scrubbed.isDeleted)
        #expect(scrubbed.senderUID.isEmpty)
        #expect(scrubbed.senderNickname == "알 수 없는 사용자")
        #expect(scrubbed.senderAvatarPath == nil)
        #expect(scrubbed.sentAt == target.sentAt)
        #expect(scrubbed.msg == nil)
        #expect(scrubbed.attachments.isEmpty)
    }

    @Test func authoritativeRegularTombstoneRepairsLegacyAnonymousMarker() async throws {
        let database = try TemporaryAppDatabase.make()
        let messageStore = GRDBChatMessageStore(database: database)
        let deletionStore = GRDBChatDeletionSyncStore(database: database)
        let original = ChatMessage(
            ID: "target",
            seq: 1,
            roomID: "room-1",
            senderUID: "user-1",
            senderNickname: "User",
            senderAvatarPath: "profiles/user-1/avatar",
            messageType: .text,
            msg: "삭제 전 원문",
            sentAt: Date(timeIntervalSince1970: 1),
            attachments: [],
            replyPreview: ReplyPreview(
                messageID: "source",
                sender: "Earlier User",
                text: "이전 메시지"
            )
        )
        try await messageStore.saveChatMessages([original])
        _ = try await deletionStore.apply(
            [ChatDeletionDelta(
                messageID: original.ID,
                roomID: original.roomID,
                seq: original.seq,
                revision: 1,
                deletedAt: Date(timeIntervalSince1970: 2),
                anonymizesSender: true
            )],
            accountID: "account-1",
            roomID: original.roomID
        )

        let serverTombstone = ChatMessage(
            ID: original.ID,
            seq: original.seq,
            roomID: original.roomID,
            senderUID: original.senderUID,
            senderNickname: original.senderNickname,
            senderAvatarPath: original.senderAvatarPath,
            messageType: nil,
            msg: nil,
            sentAt: original.sentAt,
            attachments: [],
            replyPreview: original.replyPreview,
            isDeleted: true,
            deletionRevision: 1,
            deletedAt: Date(timeIntervalSince1970: 2)
        )
        let useCase = ChatDeletionSyncUseCase(
            repository: StubChatDeletionSyncRepository(head: 1, deltas: []),
            persistence: deletionStore,
            mediaCleaner: NoopChatDeletionMediaCleaner()
        )

        let sanitized = try await useCase.sanitize(
            [serverTombstone],
            accountID: "account-1",
            roomID: original.roomID
        )
        let repaired = try #require(sanitized.first)
        #expect(repaired.senderUID == original.senderUID)
        #expect(repaired.senderNickname == original.senderNickname)
        #expect(repaired.senderAvatarPath == original.senderAvatarPath)
        #expect(repaired.sentAt == original.sentAt)
        #expect(repaired.replyPreview == original.replyPreview)
        #expect(repaired.msg == nil)

        try await messageStore.saveChatMessages([repaired])
        let persisted = try #require(await messageStore.fetchMessage(id: original.ID, inRoom: original.roomID))
        let sanitizedAgain = try #require(
            try await deletionStore.sanitize(
                [persisted],
                accountID: "account-1",
                roomID: original.roomID
            ).first
        )
        #expect(sanitizedAgain.senderUID == original.senderUID)
        #expect(sanitizedAgain.senderNickname == original.senderNickname)
        #expect(sanitizedAgain.senderAvatarPath == original.senderAvatarPath)
        #expect(sanitizedAgain.sentAt == original.sentAt)
        #expect(sanitizedAgain.replyPreview == original.replyPreview)
    }

    @Test func sanitizerAcceptsDuplicateIDsAndPrefersAuthoritativeTombstone() async throws {
        let database = try TemporaryAppDatabase.make()
        let deletionStore = GRDBChatDeletionSyncStore(database: database)
        let visible = GRDBTestFixtures.message(id: "target", seq: 1, text: "삭제 전 원문")
        let tombstone = ChatMessage(
            ID: visible.ID,
            seq: visible.seq,
            roomID: visible.roomID,
            senderUID: visible.senderUID,
            senderNickname: visible.senderNickname,
            senderAvatarPath: visible.senderAvatarPath,
            messageType: nil,
            msg: nil,
            sentAt: visible.sentAt,
            attachments: [],
            isDeleted: true,
            deletionRevision: 1,
            deletedAt: Date(timeIntervalSince1970: 2)
        )
        let useCase = ChatDeletionSyncUseCase(
            repository: StubChatDeletionSyncRepository(head: 1, deltas: []),
            persistence: deletionStore,
            mediaCleaner: NoopChatDeletionMediaCleaner()
        )

        let sanitized = try await useCase.sanitize(
            [visible, tombstone],
            accountID: "account-1",
            roomID: visible.roomID
        )

        #expect(sanitized.count == 2)
        #expect(sanitized.map(\.isDeleted) == [true, true])
        #expect(sanitized.map(\.msg) == [nil, nil])
    }

    @Test func revisionGapRollsBackScrubAndCursor() async throws {
        let database = try TemporaryAppDatabase.make()
        let messageStore = GRDBChatMessageStore(database: database)
        let deletionStore = GRDBChatDeletionSyncStore(database: database)
        try await messageStore.saveChatMessages([GRDBTestFixtures.message(id: "target")])

        await #expect(throws: ChatDeletionSyncError.revisionGap(expected: 1, actual: 2)) {
            _ = try await deletionStore.apply(
                [ChatDeletionDelta(
                    messageID: "target",
                    roomID: "room-1",
                    seq: 1,
                    revision: 2,
                    deletedAt: nil
                )],
                accountID: "account-1",
                roomID: "room-1"
            )
        }

        let message = try #require(await messageStore.fetchMessage(id: "target", inRoom: "room-1"))
        #expect(!message.isDeleted)
        #expect(try await deletionStore.cursor(accountID: "account-1", roomID: "room-1") == 0)
    }

    @Test func sanitizerChecksUnknownReplyTargetAndPersistsMarker() async throws {
        let database = try TemporaryAppDatabase.make()
        let messageStore = GRDBChatMessageStore(database: database)
        let deletionStore = GRDBChatDeletionSyncStore(database: database)
        let reply = ChatMessage(
            ID: "reply",
            seq: 2,
            roomID: "room-1",
            senderUID: "user-2",
            senderNickname: "Reply User",
            senderAvatarPath: nil,
            messageType: .text,
            msg: "좋아요",
            sentAt: Date(timeIntervalSince1970: 2),
            attachments: [],
            replyPreview: ReplyPreview(
                messageID: "missing-target",
                sender: "Original User",
                text: "민감한 원문",
                sentAt: Date(timeIntervalSince1970: 1)
            )
        )
        try await messageStore.saveChatMessages([reply])
        let repository = StubChatDeletionSyncRepository(
            head: 1,
            deltas: [ChatDeletionDelta(
                messageID: "missing-target",
                roomID: "room-1",
                seq: 1,
                revision: 1,
                deletedAt: Date(timeIntervalSince1970: 3)
            )]
        )
        let useCase = ChatDeletionSyncUseCase(
            repository: repository,
            persistence: deletionStore,
            mediaCleaner: NoopChatDeletionMediaCleaner()
        )

        let result = try await useCase.sanitize([reply], accountID: "account-1", roomID: "room-1")

        #expect(result.first?.replyPreview?.isDeleted == true)
        #expect(result.first?.replyPreview?.sender.isEmpty == true)
        #expect(result.first?.replyPreview?.text.isEmpty == true)
        let persisted = try #require(await messageStore.fetchMessage(id: "reply", inRoom: "room-1"))
        #expect(persisted.replyPreview?.isDeleted == true)
    }
}

private actor StubChatDeletionSyncRepository: ChatDeletionSyncRepositoryProtocol {
    let head: Int64
    let storedDeltas: [ChatDeletionDelta]
    private var pageRequests = 0

    init(head: Int64, deltas: [ChatDeletionDelta]) {
        self.head = head
        self.storedDeltas = deltas
    }

    func headRevision(roomID: String) async throws -> Int64 { head }

    func deltas(roomID: String, afterRevision: Int64, limit: Int) async throws -> [ChatDeletionDelta] {
        pageRequests += 1
        return Array(storedDeltas.filter { $0.revision > afterRevision }.prefix(limit))
    }

    func deltas(roomID: String, messageIDs: [String]) async throws -> [ChatDeletionDelta] {
        let ids = Set(messageIDs)
        return storedDeltas.filter { ids.contains($0.messageID) }
    }

    func pageRequestCount() -> Int { pageRequests }
}

private struct NoopChatDeletionMediaCleaner: ChatDeletionMediaCleaning {
    func clean(_ item: ChatDeletionCleanupItem) async throws {}
}
