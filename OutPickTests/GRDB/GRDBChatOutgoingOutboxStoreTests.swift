import Foundation
import Testing
@testable import OutPick

struct GRDBChatOutgoingOutboxStoreTests {
    @Test func lateStatusWriteCannotResurrectConfirmedOutbox() async throws {
        let database = try TemporaryAppDatabase.make()
        let store = GRDBChatOutgoingOutboxStore(database: database)
        let stale = ChatOutgoingOutboxRecord(messageID: "confirmed", roomID: "room-1", kind: .images,
            stage: .failed, createdAt: Date(), updatedAt: Date(), localPayloadJSON: "{}",
            uploadedPayloadJSON: nil, lastError: "timeout")
        try await store.saveOutgoingOutboxRecord(stale)
        try await GRDBChatMessageStore(database: database).saveChatMessages([GRDBTestFixtures.message(id: "confirmed", seq: 42)])
        try await store.deleteOutgoingOutboxRecord(messageID: "confirmed")
        try await store.saveOutgoingOutboxRecord(stale)
        #expect(try await store.fetchOutgoingOutboxRecord(messageID: "confirmed") == nil)
    }

    @Test func outboxRecordRoundTripsAndDeletes() async throws {
        let store = GRDBChatOutgoingOutboxStore(database: try TemporaryAppDatabase.make())
        let record = ChatOutgoingOutboxRecord(
            messageID: "message-1", roomID: "room-1", kind: .images, stage: .needsUpload,
            createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 2),
            localPayloadJSON: "{}", uploadedPayloadJSON: nil, lastError: "error"
        )

        try await store.saveOutgoingOutboxRecord(record)
        let restored = try await store.fetchOutgoingOutboxRecord(messageID: "message-1")
        #expect(restored == record)

        try await store.deleteOutgoingOutboxRecord(messageID: "message-1")
        #expect(try await store.fetchOutgoingOutboxRecord(messageID: "message-1") == nil)
    }


    @Test func roomScopedFetchAndDeleteDoNotTouchOtherRooms() async throws {
        let store = GRDBChatOutgoingOutboxStore(database: try TemporaryAppDatabase.make())
        for (messageID, roomID) in [("message-1", "room-1"), ("message-2", "room-2")] {
            try await store.saveOutgoingOutboxRecord(ChatOutgoingOutboxRecord(
                messageID: messageID, roomID: roomID, kind: .text, stage: .failed,
                createdAt: Date(), updatedAt: Date(), localPayloadJSON: nil,
                uploadedPayloadJSON: nil, lastError: nil
            ))
        }
        #expect(try await store.fetchOutgoingOutboxRecords(roomID: "room-1").map(\.messageID) == ["message-1"])
        try await store.deleteOutgoingOutboxRecords(roomID: "room-1")
        #expect(try await store.fetchOutgoingOutboxRecord(messageID: "message-1") == nil)
        #expect(try await store.fetchOutgoingOutboxRecord(messageID: "message-2") != nil)
    }
}
