//
//  CommentInteractionStore.swift
//  OutPick
//
//  Created by Codex on 5/11/26.
//

import Foundation

struct CommentInteractionState: Equatable {
    let commentID: CommentID
    var replyCount: Int
    var isHidden: Bool
    var updatedAt: Date
}

struct CommentInteractionStore {
    private var cache: PinAwareInteractionCache<CommentID, CommentInteractionState>

    init(
        maxCommentStateCount: Int,
        stateRetentionInterval: TimeInterval
    ) {
        self.cache = PinAwareInteractionCache(
            maxCount: maxCommentStateCount,
            retentionInterval: stateRetentionInterval
        )
    }

    var replyCounts: [CommentID: Int] {
        cache.valuesByKey.reduce(into: [:]) { result, item in
            result[item.key] = item.value.replyCount
        }
    }

    mutating func replyCount(for comment: Comment) -> Int {
        cache.value(for: comment.id)?.replyCount ?? comment.replyCount
    }

    mutating func pin(_ commentIDs: Set<CommentID>) {
        cache.pin(commentIDs)
    }

    mutating func unpin(_ commentIDs: Set<CommentID>) {
        cache.unpin(commentIDs)
    }

    mutating func applyReplyCount(_ replyCount: Int, for commentID: CommentID) {
        let now = Date()
        if cache.value(for: commentID, now: now) == nil {
            cache.set(
                CommentInteractionState(
                    commentID: commentID,
                    replyCount: max(0, replyCount),
                    isHidden: false,
                    updatedAt: now
                ),
                for: commentID,
                now: now
            )
            return
        }

        cache.update(for: commentID, now: now) { state in
            state.replyCount = max(0, replyCount)
            state.updatedAt = now
        }
    }

    mutating func hide(_ commentID: CommentID) {
        let now = Date()
        guard cache.value(for: commentID, now: now) != nil else { return }
        cache.update(for: commentID, now: now) { state in
            state.isHidden = true
            state.updatedAt = now
        }
    }
}
