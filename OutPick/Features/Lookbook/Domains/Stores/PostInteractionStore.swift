//
//  PostInteractionStore.swift
//  OutPick
//
//  Created by Codex on 5/11/26.
//

import Foundation

struct PostInteractionStore {
    private var cache: PinAwareInteractionCache<PostInteractionKey, LookbookPostInteractionState>

    init(
        maxPostStateCount: Int,
        stateRetentionInterval: TimeInterval
    ) {
        self.cache = PinAwareInteractionCache(
            maxCount: maxPostStateCount,
            retentionInterval: stateRetentionInterval
        )
    }

    var states: [PostInteractionKey: LookbookPostInteractionState] {
        cache.valuesByKey
    }

    mutating func state(for key: PostInteractionKey) -> LookbookPostInteractionState? {
        cache.value(for: key)
    }

    mutating func pin(_ keys: Set<PostInteractionKey>) {
        cache.pin(keys)
    }

    mutating func unpin(_ keys: Set<PostInteractionKey>) {
        cache.unpin(keys)
    }

    mutating func seed(
        post: LookbookPost,
        visibleCommentCount: Int?,
        userState: PostUserState?
    ) {
        let key = PostInteractionKey(post: post)
        cache.set(
            LookbookPostInteractionState(
                key: key,
                postID: post.id,
                post: post,
                metrics: post.metrics,
                visibleCommentCount: visibleCommentCount,
                userState: userState,
                updatedAt: Date()
            ),
            for: key
        )
    }

    mutating func seedPostMetrics(_ post: LookbookPost) {
        let key = PostInteractionKey(post: post)
        let existingState = state(for: key)
        cache.set(
            LookbookPostInteractionState(
                key: key,
                postID: post.id,
                post: post,
                metrics: post.metrics,
                visibleCommentCount: existingState?.visibleCommentCount,
                userState: existingState?.userState,
                updatedAt: Date()
            ),
            for: key
        )
    }

    mutating func applyOptimisticLike(
        key: PostInteractionKey,
        userID: UserID,
        isLiked: Bool,
        baseLiked: Bool?,
        baseLikeCount: Int?
    ) {
        cache.update(for: key) { state in
            let previousLiked = baseLiked ?? state.userState?.isLiked ?? false
            let currentLikeCount = baseLikeCount ?? state.metrics.likeCount
            let likeDelta = isLiked == previousLiked ? 0 : (isLiked ? 1 : -1)
            state.metrics = PostMetrics(
                likeCount: max(0, currentLikeCount + likeDelta),
                commentCount: state.metrics.commentCount,
                replacementCount: state.metrics.replacementCount,
                saveCount: state.metrics.saveCount,
                viewCount: state.metrics.viewCount
            )
            state.userState = PostUserState(
                postID: key.postID,
                userID: userID,
                isLiked: isLiked,
                isSaved: state.userState?.isSaved ?? false,
                updatedAt: Date()
            )
            state.updatedAt = Date()
        }
    }

    mutating func applyOptimisticSave(
        key: PostInteractionKey,
        userID: UserID,
        isSaved: Bool,
        baseSaved: Bool?,
        baseSaveCount: Int?
    ) {
        cache.update(for: key) { state in
            let previousSaved = baseSaved ?? state.userState?.isSaved ?? false
            let currentSaveCount = baseSaveCount ?? state.metrics.saveCount
            let saveDelta = isSaved == previousSaved ? 0 : (isSaved ? 1 : -1)
            state.metrics = PostMetrics(
                likeCount: state.metrics.likeCount,
                commentCount: state.metrics.commentCount,
                replacementCount: state.metrics.replacementCount,
                saveCount: max(0, currentSaveCount + saveDelta),
                viewCount: state.metrics.viewCount
            )
            state.userState = PostUserState(
                postID: key.postID,
                userID: userID,
                isLiked: state.userState?.isLiked ?? false,
                isSaved: isSaved,
                updatedAt: Date()
            )
            state.updatedAt = Date()
        }
    }

    mutating func applyLikeResult(
        _ result: PostEngagementResult,
        shouldApplySave: Bool
    ) {
        cache.update(for: result.key) { state in
            state.metrics = PostMetrics(
                likeCount: max(0, result.metrics.likeCount),
                commentCount: result.metrics.commentCount,
                replacementCount: result.metrics.replacementCount,
                saveCount: shouldApplySave ? max(0, result.metrics.saveCount) : state.metrics.saveCount,
                viewCount: result.metrics.viewCount
            )
            state.userState = PostUserState(
                postID: result.postID,
                userID: result.userID,
                isLiked: result.isLiked,
                isSaved: shouldApplySave ? result.isSaved : (state.userState?.isSaved ?? false),
                updatedAt: Date()
            )
            state.updatedAt = Date()
        }
    }

    mutating func applySaveResult(
        _ result: PostEngagementResult,
        shouldApplyLike: Bool
    ) {
        cache.update(for: result.key) { state in
            state.metrics = PostMetrics(
                likeCount: shouldApplyLike ? max(0, result.metrics.likeCount) : state.metrics.likeCount,
                commentCount: result.metrics.commentCount,
                replacementCount: result.metrics.replacementCount,
                saveCount: max(0, result.metrics.saveCount),
                viewCount: result.metrics.viewCount
            )
            state.userState = PostUserState(
                postID: result.postID,
                userID: result.userID,
                isLiked: shouldApplyLike ? result.isLiked : (state.userState?.isLiked ?? false),
                isSaved: result.isSaved,
                updatedAt: Date()
            )
            state.updatedAt = Date()
        }
    }

    mutating func restoreLike(
        key: PostInteractionKey,
        userID: UserID,
        isLiked: Bool,
        likeCount: Int?
    ) {
        cache.update(for: key) { state in
            if let likeCount {
                state.metrics = PostMetrics(
                    likeCount: max(0, likeCount),
                    commentCount: state.metrics.commentCount,
                    replacementCount: state.metrics.replacementCount,
                    saveCount: state.metrics.saveCount,
                    viewCount: state.metrics.viewCount
                )
            }
            state.userState = PostUserState(
                postID: key.postID,
                userID: userID,
                isLiked: isLiked,
                isSaved: state.userState?.isSaved ?? false,
                updatedAt: Date()
            )
            state.updatedAt = Date()
        }
    }

    mutating func restoreSave(
        key: PostInteractionKey,
        userID: UserID,
        isSaved: Bool,
        saveCount: Int?
    ) {
        cache.update(for: key) { state in
            if let saveCount {
                state.metrics = PostMetrics(
                    likeCount: state.metrics.likeCount,
                    commentCount: state.metrics.commentCount,
                    replacementCount: state.metrics.replacementCount,
                    saveCount: max(0, saveCount),
                    viewCount: state.metrics.viewCount
                )
            }
            state.userState = PostUserState(
                postID: key.postID,
                userID: userID,
                isLiked: state.userState?.isLiked ?? false,
                isSaved: isSaved,
                updatedAt: Date()
            )
            state.updatedAt = Date()
        }
    }

    mutating func applyCommentMutation(_ result: CommentMutationResult) {
        cache.update(for: PostInteractionKey(
            brandID: result.brandID,
            seasonID: result.seasonID,
            postID: result.postID
        )) { state in
            state.metrics = PostMetrics(
                likeCount: state.metrics.likeCount,
                commentCount: max(0, result.commentCount),
                replacementCount: state.metrics.replacementCount,
                saveCount: state.metrics.saveCount,
                viewCount: state.metrics.viewCount
            )
            state.visibleCommentCount = state.visibleCommentCount.map { max(0, $0 + 1) }
            state.updatedAt = Date()
        }
    }

    mutating func applyCommentDeletion(_ result: CommentDeletionResult) {
        cache.update(for: PostInteractionKey(
            brandID: result.brandID,
            seasonID: result.seasonID,
            postID: result.postID
        )) { state in
            state.metrics = PostMetrics(
                likeCount: state.metrics.likeCount,
                commentCount: max(0, result.commentCount),
                replacementCount: state.metrics.replacementCount,
                saveCount: state.metrics.saveCount,
                viewCount: state.metrics.viewCount
            )
            state.visibleCommentCount = state.visibleCommentCount.map {
                max(0, $0 - max(1, result.deletedCommentCount))
            }
            state.updatedAt = Date()
        }
    }
}
