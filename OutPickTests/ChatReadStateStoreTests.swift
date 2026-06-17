//
//  ChatReadStateStoreTests.swift
//  OutPickTests
//
//  Created by Codex on 6/18/26.
//

import Testing
@testable import OutPick

struct ChatReadStateStoreTests {
    @Test func nextCandidateRequiresNearBottomUnlessSkipped() {
        var store = ChatReadStateStore()

        #expect(store.nextCandidate(windowMaxSeq: 10, isNearBottom: false, skipNearBottomCheck: false) == nil)
        #expect(store.nextCandidate(windowMaxSeq: 10, isNearBottom: false, skipNearBottomCheck: true) == 10)

        store.queue(10)
        #expect(store.nextCandidate(windowMaxSeq: 10, isNearBottom: true, skipNearBottomCheck: false) == nil)
        #expect(store.nextCandidate(windowMaxSeq: 11, isNearBottom: true, skipNearBottomCheck: false) == 11)
    }

    @Test func queueKeepsMonotonicPendingAndQueuedSeq() {
        var store = ChatReadStateStore()

        store.queue(5)
        store.queue(3)
        store.queue(8)

        #expect(store.pendingLastReadSeq == 8)
        #expect(store.queuedLastReadSeq == 8)
        #expect(store.pendingFlushSeq() == 8)
    }

    @Test func markFlushedUpdatesPersistedSeqAndClearsPendingWhenCovered() {
        var store = ChatReadStateStore()

        store.queue(7)
        store.markFlushed(7)

        #expect(store.persistedLastReadSeq == 7)
        #expect(store.pendingLastReadSeq == 0)
        #expect(store.pendingFlushSeq() == nil)
        #expect(store.nextCandidate(windowMaxSeq: 7, isNearBottom: true, skipNearBottomCheck: false) == nil)
        #expect(store.nextCandidate(windowMaxSeq: 9, isNearBottom: true, skipNearBottomCheck: false) == 9)
    }

    @Test func finalSeqUsesWindowPendingQueuedAndPersistedMax() {
        var store = ChatReadStateStore()

        #expect(store.finalSeqForSessionEnd(windowMaxSeq: 4) == 4)

        store.queue(9)
        #expect(store.finalSeqForSessionEnd(windowMaxSeq: 4) == 9)

        store.markFlushed(12)
        #expect(store.finalSeqForSessionEnd(windowMaxSeq: 4) == 12)
    }

    @Test func resetClearsQueuedPendingAndPersistedSeq() {
        var store = ChatReadStateStore()

        store.queue(9)
        store.markFlushed(9)
        store.queue(10)
        store.reset()

        #expect(store.pendingLastReadSeq == 0)
        #expect(store.queuedLastReadSeq == 0)
        #expect(store.persistedLastReadSeq == 0)
        #expect(store.pendingFlushSeq() == nil)
    }
}
