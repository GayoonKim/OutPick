//
//  JoinedRoomsSessionStoreTests.swift
//  OutPickTests
//
//  Created by Codex on 6/25/26.
//

import Testing
@testable import OutPick

@MainActor
struct JoinedRoomsSessionStoreTests {
    @Test func replaceAddRemoveAndClearUpdateSnapshot() {
        let store = JoinedRoomsSessionStore()

        store.replace(with: ["room-1", "room-2", "room-1"])
        #expect(store.joined == ["room-1", "room-2"])
        #expect(store.contains("room-1"))

        store.add("room-3")
        #expect(store.joined == ["room-1", "room-2", "room-3"])

        store.remove("room-2")
        #expect(store.joined == ["room-1", "room-3"])

        store.clear()
        #expect(store.joined.isEmpty)
    }

    @Test func duplicateChangesDoNotMutateSnapshot() {
        let store = JoinedRoomsSessionStore()

        store.replace(with: ["room-1"])
        store.replace(with: ["room-1"])
        store.add("room-1")
        store.remove("missing-room")
        #expect(store.joined == ["room-1"])

        store.remove("room-1")
        #expect(store.joined.isEmpty)
    }

    @Test func changeStreamPublishesSnapshotsAfterMutations() async {
        let store = JoinedRoomsSessionStore()
        var iterator = store.changeStream().makeAsyncIterator()

        let initial = await iterator.next()
        #expect(initial == [])

        store.replace(with: ["room-1", "room-2"])
        let replaced = await iterator.next()
        #expect(replaced == ["room-1", "room-2"])

        store.remove("room-1")
        let removed = await iterator.next()
        #expect(removed == ["room-2"])

        store.clear()
        let cleared = await iterator.next()
        #expect(cleared == [])
    }
}
