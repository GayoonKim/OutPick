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
    private(set) var pendingLastReadUnreadMessageSeq: Int64 = 0
    private(set) var queuedLastReadUnreadMessageSeq: Int64 = 0
    private(set) var persistedLastReadUnreadMessageSeq: Int64 = 0

    var frontierSeq: Int64 {
        max(pendingLastReadSeq, queuedLastReadSeq, persistedLastReadSeq)
    }

    mutating func reset(
        persistedLastReadSeq: Int64 = 0,
        persistedLastReadUnreadMessageSeq: Int64? = nil
    ) {
        let normalizedPersistedSeq = max(Int64(0), persistedLastReadSeq)
        let normalizedUnreadSeq = max(
            Int64(0),
            persistedLastReadUnreadMessageSeq ?? normalizedPersistedSeq
        )
        pendingLastReadSeq = 0
        queuedLastReadSeq = normalizedPersistedSeq
        self.persistedLastReadSeq = normalizedPersistedSeq
        pendingLastReadUnreadMessageSeq = 0
        queuedLastReadUnreadMessageSeq = normalizedUnreadSeq
        self.persistedLastReadUnreadMessageSeq = normalizedUnreadSeq
    }

    func finalSeqForSessionEnd() -> Int64 {
        frontierSeq
    }

    @discardableResult
    mutating func queueVisibleCandidate(
        _ visibleSeq: Int64,
        contiguousLoadedThroughSeq: Int64,
        unreadMessageSeq: Int64? = nil
    ) -> Int64? {
        let currentFrontier = frontierSeq
        guard visibleSeq > currentFrontier,
              contiguousLoadedThroughSeq > currentFrontier else {
            return nil
        }

        let candidate = min(visibleSeq, contiguousLoadedThroughSeq)
        guard candidate > currentFrontier else { return nil }

        queue(candidate, unreadMessageSeq: unreadMessageSeq)
        return candidate
    }

    @discardableResult
    mutating func queueExplicitJumpTarget(
        _ targetSeq: Int64,
        unreadMessageSeq: Int64? = nil
    ) -> Int64? {
        guard targetSeq > frontierSeq else { return nil }
        queue(targetSeq, unreadMessageSeq: unreadMessageSeq)
        return targetSeq
    }

    mutating func queue(_ seq: Int64, unreadMessageSeq: Int64? = nil) {
        guard seq > 0 else { return }
        if seq > queuedLastReadSeq {
            queuedLastReadSeq = seq
        }
        if seq > pendingLastReadSeq {
            pendingLastReadSeq = seq
        }
        let resolvedUnreadSeq = max(
            frontierUnreadMessageSeq,
            unreadMessageSeq ?? seq
        )
        queuedLastReadUnreadMessageSeq = max(queuedLastReadUnreadMessageSeq, resolvedUnreadSeq)
        pendingLastReadUnreadMessageSeq = max(pendingLastReadUnreadMessageSeq, resolvedUnreadSeq)
    }

    var frontierUnreadMessageSeq: Int64 {
        max(
            pendingLastReadUnreadMessageSeq,
            queuedLastReadUnreadMessageSeq,
            persistedLastReadUnreadMessageSeq
        )
    }

    func pendingFlushSeq() -> Int64? {
        guard pendingLastReadSeq > persistedLastReadSeq else { return nil }
        return pendingLastReadSeq
    }

    func pendingFlushFrontier() -> (timelineSeq: Int64, unreadMessageSeq: Int64)? {
        guard let timelineSeq = pendingFlushSeq() else { return nil }
        return (timelineSeq, frontierUnreadMessageSeq)
    }

    mutating func markFlushed(_ seq: Int64, unreadMessageSeq: Int64? = nil) {
        guard seq > 0 else { return }
        persistedLastReadSeq = max(persistedLastReadSeq, seq)
        queuedLastReadSeq = max(queuedLastReadSeq, persistedLastReadSeq)
        if pendingLastReadSeq <= persistedLastReadSeq {
            pendingLastReadSeq = 0
        }
        if let unreadMessageSeq {
            persistedLastReadUnreadMessageSeq = max(
                persistedLastReadUnreadMessageSeq,
                unreadMessageSeq
            )
            queuedLastReadUnreadMessageSeq = max(
                queuedLastReadUnreadMessageSeq,
                persistedLastReadUnreadMessageSeq
            )
            if pendingLastReadUnreadMessageSeq <= persistedLastReadUnreadMessageSeq {
                pendingLastReadUnreadMessageSeq = 0
            }
        }
    }
}
