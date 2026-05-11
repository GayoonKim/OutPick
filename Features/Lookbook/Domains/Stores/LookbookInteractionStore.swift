//
//  LookbookInteractionStore.swift
//  OutPick
//
//  Created by Codex on 5/7/26.
//

import Combine
import Foundation

struct LookbookPostInteractionState: Equatable {
    let postID: PostID
    var metrics: PostMetrics
    var visibleCommentCount: Int?
    var userState: PostUserState?
    var updatedAt: Date
}

@MainActor
final class LookbookInteractionStore: ObservableObject {
    @Published private(set) var postStates: [PostID: LookbookPostInteractionState] = [:]
    @Published private(set) var replyCounts: [CommentID: Int] = [:]

    private let maxPostStateCount: Int
    private let maxReplyCount: Int
    private let stateRetentionInterval: TimeInterval
    private var replyCountUpdatedAt: [CommentID: Date] = [:]

    init(
        maxPostStateCount: Int = 300,
        maxReplyCount: Int = 600,
        stateRetentionInterval: TimeInterval = 60 * 60
    ) {
        self.maxPostStateCount = max(1, maxPostStateCount)
        self.maxReplyCount = max(1, maxReplyCount)
        self.stateRetentionInterval = max(60, stateRetentionInterval)
    }

    func state(for postID: PostID) -> LookbookPostInteractionState? {
        postStates[postID]
    }

    func replyCount(for comment: Comment) -> Int {
        replyCounts[comment.id] ?? comment.replyCount
    }

    func seed(
        post: LookbookPost,
        visibleCommentCount: Int?,
        userState: PostUserState?
    ) {
        postStates[post.id] = LookbookPostInteractionState(
            postID: post.id,
            metrics: post.metrics,
            visibleCommentCount: visibleCommentCount,
            userState: userState,
            updatedAt: Date()
        )
        pruneExpiredStates()
    }

    func seedPostMetrics(_ post: LookbookPost) {
        let existingState = postStates[post.id]
        postStates[post.id] = LookbookPostInteractionState(
            postID: post.id,
            metrics: post.metrics,
            visibleCommentCount: existingState?.visibleCommentCount,
            userState: existingState?.userState,
            updatedAt: Date()
        )
        pruneExpiredStates()
    }

    func applyOptimisticLike(
        postID: PostID,
        userID: UserID,
        isLiked: Bool,
        baseLiked: Bool? = nil,
        baseLikeCount: Int? = nil
    ) {
        guard var state = postStates[postID] else { return }

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
            postID: postID,
            userID: userID,
            isLiked: isLiked,
            isSaved: state.userState?.isSaved ?? false,
            updatedAt: Date()
        )
        state.updatedAt = Date()
        postStates[postID] = state
        pruneExpiredStates()
    }

    func applyOptimisticSave(
        postID: PostID,
        userID: UserID,
        isSaved: Bool,
        baseSaved: Bool? = nil,
        baseSaveCount: Int? = nil
    ) {
        guard var state = postStates[postID] else { return }

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
            postID: postID,
            userID: userID,
            isLiked: state.userState?.isLiked ?? false,
            isSaved: isSaved,
            updatedAt: Date()
        )
        state.updatedAt = Date()
        postStates[postID] = state
        pruneExpiredStates()
    }

    func applyLikeResult(
        _ result: PostEngagementResult,
        shouldApplySave: Bool
    ) {
        guard var state = postStates[result.postID] else { return }

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
        postStates[result.postID] = state
        pruneExpiredStates()
    }

    func applySaveResult(
        _ result: PostEngagementResult,
        shouldApplyLike: Bool
    ) {
        guard var state = postStates[result.postID] else { return }

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
        postStates[result.postID] = state
        pruneExpiredStates()
    }

    func restoreLike(
        postID: PostID,
        userID: UserID,
        isLiked: Bool,
        likeCount: Int?
    ) {
        guard var state = postStates[postID] else { return }

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
            postID: postID,
            userID: userID,
            isLiked: isLiked,
            isSaved: state.userState?.isSaved ?? false,
            updatedAt: Date()
        )
        state.updatedAt = Date()
        postStates[postID] = state
        pruneExpiredStates()
    }

    func restoreSave(
        postID: PostID,
        userID: UserID,
        isSaved: Bool,
        saveCount: Int?
    ) {
        guard var state = postStates[postID] else { return }

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
            postID: postID,
            userID: userID,
            isLiked: state.userState?.isLiked ?? false,
            isSaved: isSaved,
            updatedAt: Date()
        )
        state.updatedAt = Date()
        postStates[postID] = state
        pruneExpiredStates()
    }

    func applyCommentMutation(_ result: CommentMutationResult) {
        guard var state = postStates[result.postID] else { return }

        state.metrics = PostMetrics(
            likeCount: state.metrics.likeCount,
            commentCount: max(0, result.commentCount),
            replacementCount: state.metrics.replacementCount,
            saveCount: state.metrics.saveCount,
            viewCount: state.metrics.viewCount
        )
        state.visibleCommentCount = state.visibleCommentCount.map { max(0, $0 + 1) }
        if let parentCommentID = result.parentCommentID {
            replyCounts[parentCommentID] = max(0, result.replyCount)
            replyCountUpdatedAt[parentCommentID] = Date()
        }
        state.updatedAt = Date()
        postStates[result.postID] = state
        pruneExpiredStates()
    }

    func applyCommentDeletion(_ result: CommentDeletionResult) {
        guard var state = postStates[result.postID] else { return }

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
        if let parentCommentID = result.parentCommentID {
            replyCounts[parentCommentID] = max(0, result.replyCount)
            replyCountUpdatedAt[parentCommentID] = Date()
        }
        state.updatedAt = Date()
        postStates[result.postID] = state
        pruneExpiredStates()
    }

    private func pruneExpiredStates(now: Date = Date()) {
        prunePostStates(now: now)
        pruneReplyCounts(now: now)
    }

    private func prunePostStates(now: Date) {
        let cutoff = now.addingTimeInterval(-stateRetentionInterval)
        postStates = postStates.filter { _, state in
            state.updatedAt >= cutoff
        }

        guard postStates.count > maxPostStateCount else { return }
        let idsToRemove = postStates
            .sorted { $0.value.updatedAt < $1.value.updatedAt }
            .prefix(postStates.count - maxPostStateCount)
            .map(\.key)

        for id in idsToRemove {
            postStates.removeValue(forKey: id)
        }
    }

    private func pruneReplyCounts(now: Date) {
        let cutoff = now.addingTimeInterval(-stateRetentionInterval)
        let expiredIDs = replyCountUpdatedAt
            .filter { $0.value < cutoff }
            .map(\.key)

        for id in expiredIDs {
            replyCounts.removeValue(forKey: id)
            replyCountUpdatedAt.removeValue(forKey: id)
        }

        guard replyCounts.count > maxReplyCount else { return }
        let idsToRemove = replyCountUpdatedAt
            .sorted { $0.value < $1.value }
            .prefix(replyCounts.count - maxReplyCount)
            .map(\.key)

        for id in idsToRemove {
            replyCounts.removeValue(forKey: id)
            replyCountUpdatedAt.removeValue(forKey: id)
        }
    }
}
