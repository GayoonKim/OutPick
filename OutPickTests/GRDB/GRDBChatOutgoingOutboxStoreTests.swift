import Foundation
import Testing
@testable import OutPick

struct GRDBChatOutgoingOutboxStoreTests {
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
}
