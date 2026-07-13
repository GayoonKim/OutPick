import Foundation
import Testing
@testable import OutPick

struct GRDBChatProfileCacheStoreTests {
    @Test func roomDisplayCacheEvictsLeastRecentEntries() throws {
        let store = GRDBChatProfileCacheStore(database: try TemporaryAppDatabase.make())
        let base = Date(timeIntervalSince1970: 1_000)

        for index in 0..<5 {
            try store.upsertLocalChatUser(userID: "user-\(index)", nickname: "User \(index)", profileImagePath: nil)
            try store.upsertRoomProfileDisplayCache(
                roomID: "room-1", userID: "user-\(index)",
                lastSeenAt: base.addingTimeInterval(TimeInterval(index)),
                lastMessageSeq: index, lastMessageID: "message-\(index)",
                updatedAt: base, maxEntriesPerRoom: 3
            )
        }

        #expect(try store.fetchRoomProfileDisplayCacheUserIDs(roomID: "room-1") == ["user-4", "user-3", "user-2"])
        #expect(try store.countRoomProfileDisplayCache(roomID: "room-1") == 3)
    }
}
