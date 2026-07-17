//
//  ChatReadStateStoreTests.swift
//  OutPickTests
//
//  Created by Codex on 6/18/26.
//

import Testing
@testable import OutPick

struct ChatReadStateStoreTests {
    @Test func resetSeedsPersistedFrontierAndNormalizesNegativeValue() {
        var store = ChatReadStateStore()

        store.reset(persistedLastReadSeq: 12)

        #expect(store.frontierSeq == 12)
        #expect(store.persistedLastReadSeq == 12)
        #expect(store.queuedLastReadSeq == 12)
        #expect(store.pendingLastReadSeq == 0)
        #expect(store.finalSeqForSessionEnd() == 12)

        store.reset(persistedLastReadSeq: -1)
        #expect(store.frontierSeq == 0)
    }

    @Test func visibleCandidateIsBoundedByContiguousLoadedRange() {
        var store = ChatReadStateStore()
        store.reset(persistedLastReadSeq: 10)

        let accepted = store.queueVisibleCandidate(
            25,
            contiguousLoadedThroughSeq: 20
        )

        #expect(accepted == 20)
        #expect(store.frontierSeq == 20)
        #expect(store.pendingFlushSeq() == 20)
    }

    @Test func visibleCandidateCannotCrossUnprovenGapOrMoveBackward() {
        var store = ChatReadStateStore()
        store.reset(persistedLastReadSeq: 10)

        let gapCandidate = store.queueVisibleCandidate(20, contiguousLoadedThroughSeq: 10)
        let backwardCandidate = store.queueVisibleCandidate(9, contiguousLoadedThroughSeq: 20)

        #expect(gapCandidate == nil)
        #expect(backwardCandidate == nil)
        #expect(store.frontierSeq == 10)
        #expect(store.pendingFlushSeq() == nil)
    }

    @Test func explicitJumpCanAdvanceBeyondContiguousLoadedRange() {
        var store = ChatReadStateStore()
        store.reset(persistedLastReadSeq: 10)

        let visibleCandidate = store.queueVisibleCandidate(20, contiguousLoadedThroughSeq: 10)
        let jumpCandidate = store.queueExplicitJumpTarget(10_010)
        let staleJumpCandidate = store.queueExplicitJumpTarget(10_000)

        #expect(visibleCandidate == nil)
        #expect(jumpCandidate == 10_010)
        #expect(store.frontierSeq == 10_010)
        #expect(staleJumpCandidate == nil)
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
    }

    @Test func finalSeqUsesOnlyFrontierState() {
        var store = ChatReadStateStore()

        #expect(store.finalSeqForSessionEnd() == 0)

        store.queue(9)
        #expect(store.finalSeqForSessionEnd() == 9)

        store.markFlushed(12)
        #expect(store.finalSeqForSessionEnd() == 12)
    }

    @Test func frontierFinalSeqDoesNotDependOnLoadedWindowMax() {
        var store = ChatReadStateStore()
        store.reset(persistedLastReadSeq: 10)
        _ = store.queueVisibleCandidate(15, contiguousLoadedThroughSeq: 15)

        #expect(store.finalSeqForSessionEnd() == 15)
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
