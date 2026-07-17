//
//  ChatReadStateStore.swift
//  OutPick
//
//  Created by Codex on 6/18/26.
//

import Foundation

struct ChatReadStateStore {
    private(set) var pendingLastReadSeq: Int64 = 0
    private(set) var queuedLastReadSeq: Int64 = 0
    private(set) var persistedLastReadSeq: Int64 = 0

    var frontierSeq: Int64 {
        max(pendingLastReadSeq, queuedLastReadSeq, persistedLastReadSeq)
    }

    mutating func reset(persistedLastReadSeq: Int64 = 0) {
        let normalizedPersistedSeq = max(Int64(0), persistedLastReadSeq)
        pendingLastReadSeq = 0
        queuedLastReadSeq = normalizedPersistedSeq
        self.persistedLastReadSeq = normalizedPersistedSeq
    }

    func finalSeqForSessionEnd() -> Int64 {
        frontierSeq
    }

    @discardableResult
    mutating func queueVisibleCandidate(
        _ visibleSeq: Int64,
        contiguousLoadedThroughSeq: Int64
    ) -> Int64? {
        let currentFrontier = frontierSeq
        guard visibleSeq > currentFrontier,
              contiguousLoadedThroughSeq > currentFrontier else {
            return nil
        }

        let candidate = min(visibleSeq, contiguousLoadedThroughSeq)
        guard candidate > currentFrontier else { return nil }

        queue(candidate)
        return candidate
    }

    @discardableResult
    mutating func queueExplicitJumpTarget(_ targetSeq: Int64) -> Int64? {
        guard targetSeq > frontierSeq else { return nil }
        queue(targetSeq)
        return targetSeq
    }

    mutating func queue(_ seq: Int64) {
        guard seq > 0 else { return }
        if seq > queuedLastReadSeq {
            queuedLastReadSeq = seq
        }
        if seq > pendingLastReadSeq {
            pendingLastReadSeq = seq
        }
    }

    func pendingFlushSeq() -> Int64? {
        guard pendingLastReadSeq > persistedLastReadSeq else { return nil }
        return pendingLastReadSeq
    }

    mutating func markFlushed(_ seq: Int64) {
        guard seq > 0 else { return }
        persistedLastReadSeq = max(persistedLastReadSeq, seq)
        queuedLastReadSeq = max(queuedLastReadSeq, persistedLastReadSeq)
        if pendingLastReadSeq <= persistedLastReadSeq {
            pendingLastReadSeq = 0
        }
    }
}
