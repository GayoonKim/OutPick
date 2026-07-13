import Foundation
import Testing
@testable import OutPick

struct GRDBChatMediaIndexStoreTests {
    @Test func mediaEntriesUpsertAndPaginateByNewestFirst() throws {
        let store = GRDBChatMediaIndexStore(database: try TemporaryAppDatabase.make())
        let entries = [
            makeEntry(messageID: "m1", sentAt: Date(timeIntervalSince1970: 1)),
            makeEntry(messageID: "m2", sentAt: Date(timeIntervalSince1970: 2))
        ]

        try store.upsertMediaIndexEntries(entries)

        #expect(try store.countImageIndex(inRoom: "room-1") == 2)
        #expect(try store.fetchLatestImageIndex(inRoom: "room-1", limit: 2).map(\.messageID) == ["m2", "m1"])
    }

    private func makeEntry(messageID: String, sentAt: Date) -> ChatRoomMediaIndexEntry {
        ChatRoomMediaIndexEntry(
            roomID: "room-1",
            messageID: messageID,
            idx: 0,
            seq: 1,
            senderUID: "user-1",
            type: .image,
            thumbKey: "thumb",
            originalKey: "original",
            thumbURL: "thumb-url",
            originalURL: "original-url",
            width: 10,
            height: 10,
            bytesOriginal: 100,
            duration: nil,
            hash: "hash",
            isDeleted: false,
            sentAt: sentAt
        )
    }
}
