//
//  CommentInteractionStore.swift
//  OutPick
//
//  Created by Codex on 5/11/26.
//

import Foundation

struct CommentInteractionState: Equatable {
    let commentID: CommentID
    var replyCount: Int?
    var likeCount: Int?
    var userID: UserID?
    var isLiked: Bool?
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
            guard let replyCount = item.value.replyCount else { return }
            result[item.key] = replyCount
        }
    }

    var states: [CommentID: CommentInteractionState] {
        cache.valuesByKey
    }

    mutating func state(for commentID: CommentID) -> CommentInteractionState? {
        cache.value(for: commentID)
    }

    mutating func replyCount(for comment: Comment) -> Int {
        cache.value(for: comment.id)?.replyCount ?? comment.replyCount
    }

    mutating func likeCount(for comment: Comment) -> Int {
        cache.value(for: comment.id)?.likeCount ?? comment.likeCount
    }

    mutating func isLiked(_ comment: Comment, userID: UserID?) -> Bool {
        guard let userID,
              let state = cache.value(for: comment.id),
              state.userID == userID else {
            return false
        }
        return state.isLiked ?? false
    }

    mutating func isHidden(_ commentID: CommentID) -> Bool {
        cache.value(for: commentID)?.isHidden ?? false
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
                    likeCount: nil,
                    userID: nil,
                    isLiked: nil,
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
        if cache.value(for: commentID, now: now) == nil {
            cache.set(
                CommentInteractionState(
                    commentID: commentID,
                    replyCount: nil,
                    likeCount: nil,
                    userID: nil,
                    isLiked: nil,
                    isHidden: true,
                    updatedAt: now
                ),
                for: commentID,
                now: now
            )
            return
        }

        cache.update(for: commentID, now: now) { state in
            state.isHidden = true
            state.updatedAt = now
        }
    }

    mutating func hide(_ commentIDs: Set<CommentID>) {
        for commentID in commentIDs {
            hide(commentID)
        }
    }

    mutating func seedLikeStates(
        comments: [Comment],
        userStates: [CommentID: CommentUserState],
        userID: UserID
    ) {
        let now = Date()
        for comment in comments {
            let isLiked = userStates[comment.id]?.isLiked ?? false
            upsertLikeState(
                commentID: comment.id,
                replyCount: comment.replyCount,
                likeCount: comment.likeCount,
                userID: userID,
                isLiked: isLiked,
                now: now
            )
        }
    }

    mutating func applyOptimisticLike(
        comment: Comment,
        userID: UserID,
        isLiked: Bool,
        baseLiked: Bool?,
        baseLikeCount: Int?
    ) {
        let now = Date()
        let currentState = cache.value(for: comment.id, now: now)
        let previousLiked = baseLiked ??
            (currentState?.userID == userID ? currentState?.isLiked ?? false : false)
        let likeCount = baseLikeCount ?? currentState?.likeCount ?? comment.likeCount
        let delta = optimisticLikeDelta(
            previousLiked: previousLiked,
            nextLiked: isLiked
        )
        upsertLikeState(
            commentID: comment.id,
            replyCount: comment.replyCount,
            likeCount: max(0, likeCount + delta),
            userID: userID,
            isLiked: isLiked,
            now: now
        )
    }

    mutating func applyLikeResult(_ result: CommentEngagementResult) {
        let now = Date()
        upsertLikeState(
            commentID: result.commentID,
            replyCount: nil,
            likeCount: result.likeCount,
            userID: result.userID,
            isLiked: result.isLiked,
            now: now
        )
    }

    mutating func restoreLike(
        comment: Comment,
        userID: UserID,
        isLiked: Bool,
        likeCount: Int
    ) {
        let now = Date()
        upsertLikeState(
            commentID: comment.id,
            replyCount: comment.replyCount,
            likeCount: likeCount,
            userID: userID,
            isLiked: isLiked,
            now: now
        )
    }

    private mutating func upsertLikeState(
        commentID: CommentID,
        replyCount: Int?,
        likeCount: Int,
        userID: UserID,
        isLiked: Bool,
        now: Date
    ) {
        if cache.value(for: commentID, now: now) == nil {
            cache.set(
                CommentInteractionState(
                    commentID: commentID,
                    replyCount: replyCount.map { max(0, $0) },
                    likeCount: max(0, likeCount),
                    userID: userID,
                    isLiked: isLiked,
                    isHidden: false,
                    updatedAt: now
                ),
                for: commentID,
                now: now
            )
            return
        }

        cache.update(for: commentID, now: now) { state in
            if let replyCount {
                state.replyCount = max(0, replyCount)
            }
            state.likeCount = max(0, likeCount)
            state.userID = userID
            state.isLiked = isLiked
            state.updatedAt = now
        }
    }

    private func optimisticLikeDelta(
        previousLiked: Bool,
        nextLiked: Bool
    ) -> Int {
        switch (previousLiked, nextLiked) {
        case (false, true):
            return 1
        case (true, false):
            return -1
        default:
            return 0
        }
    }
}
