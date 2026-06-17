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

    mutating func reset() {
        pendingLastReadSeq = 0
        queuedLastReadSeq = 0
        persistedLastReadSeq = 0
    }

    func finalSeqForSessionEnd(windowMaxSeq: Int64) -> Int64 {
        max(windowMaxSeq, pendingLastReadSeq, queuedLastReadSeq, persistedLastReadSeq)
    }

    func nextCandidate(
        windowMaxSeq: Int64,
        isNearBottom: Bool,
        skipNearBottomCheck: Bool
    ) -> Int64? {
        if !skipNearBottomCheck, !isNearBottom {
            return nil
        }

        let knownMax = max(queuedLastReadSeq, persistedLastReadSeq)
        guard windowMaxSeq > knownMax else { return nil }
        return windowMaxSeq
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
        if pendingLastReadSeq <= persistedLastReadSeq {
            pendingLastReadSeq = 0
        }
    }
}
