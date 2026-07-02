//
//  ChatRoomReadStateStoreTests.swift
//  OutPickTests
//
//  Created by Codex on 6/18/26.
//

import Testing
@testable import OutPick

@MainActor
struct ChatRoomReadStateStoreTests {
    @Test func snapshotCalculatesUnreadCountWithCurrentUserSenderAdjustment() {
        let snapshot = ChatRoomReadSnapshot(
            roomID: "room-1",
            latestSeq: 10,
            lastReadSeq: 7,
            lastMessageSenderUID: "me@example.com"
        )

        #expect(snapshot.unreadCount(currentUserID: "me@example.com") == 2)
        #expect(snapshot.unreadCount(currentUserID: "other@example.com") == 3)
    }

    @Test func streamEmitsOnlySubscribedRoomChanges() async {
        let store = ChatRoomReadStateStore()
        let stream = store.readStateChangeStream(for: ["room-2"])
        var iterator = stream.makeAsyncIterator()

        store.seedLatest(
            roomID: "room-1",
            latestSeq: 4,
            lastMessageSenderUID: "other@example.com"
        )
        store.seed(
            ChatRoomReadSnapshot(
                roomID: "room-2",
                latestSeq: 8,
                lastReadSeq: 3,
                lastMessageSenderUID: "other@example.com"
            )
        )

        let change = await iterator.next()
        #expect(change?.roomID == "room-2")
        #expect(change?.snapshot.latestSeq == 8)
        #expect(change?.snapshot.lastReadSeq == 3)
    }

    @Test func markReadFlushedKeepsLastReadSeqMonotonic() {
        let store = ChatRoomReadStateStore()

        store.seed(
            ChatRoomReadSnapshot(
                roomID: "room-1",
                latestSeq: 10,
                lastReadSeq: 4,
                lastMessageSenderUID: "other@example.com"
            )
        )
        store.markReadFlushed(roomID: "room-1", lastReadSeq: 9)
        store.markReadFlushed(roomID: "room-1", lastReadSeq: 6)

        let snapshot = store.snapshot(for: "room-1")
        #expect(snapshot?.lastReadSeq == 9)
        #expect(snapshot?.unreadCount(currentUserID: "me@example.com") == 1)
    }
}
