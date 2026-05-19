//
//  LookbookInteractionStore.swift
//  OutPick
//
//  Created by Codex on 5/7/26.
//

import Foundation

@MainActor
final class LookbookInteractionStore: PostInteractionManaging, CommentInteractionManaging {
    private var postStates: [PostID: LookbookPostInteractionState] = [:]
    private var postStore: PostInteractionStore
    private var commentStore: CommentInteractionStore
    private var commentStates: [CommentID: CommentInteractionState] = [:]
    private var postStateInvalidationContinuations: [UUID: (postIDs: Set<PostID>, continuation: AsyncStream<PostID>.Continuation)] = [:]
    private var commentStateInvalidationContinuations: [UUID: (commentIDs: Set<CommentID>, continuation: AsyncStream<CommentID>.Continuation)] = [:]
    private var representativeCommentInvalidationContinuations: [UUID: (postID: PostID, continuation: AsyncStream<PostID>.Continuation)] = [:]

    init(
        maxPostStateCount: Int = 300,
        maxCommentStateCount: Int = 600,
        stateRetentionInterval: TimeInterval = 60 * 60
    ) {
        self.postStore = PostInteractionStore(
            maxPostStateCount: maxPostStateCount,
            stateRetentionInterval: stateRetentionInterval
        )
        self.commentStore = CommentInteractionStore(
            maxCommentStateCount: maxCommentStateCount,
            stateRetentionInterval: stateRetentionInterval
        )
    }

    func state(for postID: PostID) -> LookbookPostInteractionState? {
        postStore.state(for: postID)
    }

    func replyCount(for comment: Comment) -> Int {
        commentStore.replyCount(for: comment)
    }

    func likeCount(for comment: Comment) -> Int {
        commentStore.likeCount(for: comment)
    }

    func isCommentLiked(_ comment: Comment, userID: UserID?) -> Bool {
        commentStore.isLiked(comment, userID: userID)
    }

    func isCommentHidden(_ commentID: CommentID) -> Bool {
        commentStore.isHidden(commentID)
    }

    func postStateInvalidationStream(
        for postIDs: Set<PostID>
    ) -> AsyncStream<PostID> {
        guard postIDs.isEmpty == false else {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }

        return AsyncStream { [weak self] continuation in
            guard let self else { return }
            let continuationID = UUID()
            self.postStateInvalidationContinuations[continuationID] = (postIDs, continuation)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.postStateInvalidationContinuations.removeValue(forKey: continuationID)
                }
            }
        }
    }

    func commentState(for commentID: CommentID) -> CommentInteractionState? {
        commentStore.state(for: commentID)
    }

    func commentStateInvalidationStream(
        for commentIDs: Set<CommentID>
    ) -> AsyncStream<CommentID> {
        guard commentIDs.isEmpty == false else {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }

        return AsyncStream { [weak self] continuation in
            guard let self else { return }
            let continuationID = UUID()
            self.commentStateInvalidationContinuations[continuationID] = (commentIDs, continuation)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.commentStateInvalidationContinuations.removeValue(forKey: continuationID)
                }
            }
        }
    }

    func representativeCommentInvalidationStream(for postID: PostID) -> AsyncStream<PostID> {
        AsyncStream { [weak self] continuation in
            guard let self else { return }
            let continuationID = UUID()
            self.representativeCommentInvalidationContinuations[continuationID] = (postID, continuation)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.representativeCommentInvalidationContinuations.removeValue(forKey: continuationID)
                }
            }
        }
    }

    func pinScope(
        postIDs: Set<PostID> = [],
        commentIDs: Set<CommentID> = []
    ) -> InteractionPinScope {
        if postIDs.isEmpty == false {
            postStore.pin(postIDs)
        }
        if commentIDs.isEmpty == false {
            commentStore.pin(commentIDs)
        }
        syncPostStates()
        syncCommentStates()

        return InteractionPinScope { [weak self] in
            guard let self else { return }
            if postIDs.isEmpty == false {
                self.postStore.unpin(postIDs)
            }
            if commentIDs.isEmpty == false {
                self.commentStore.unpin(commentIDs)
            }
            self.syncPostStates()
            self.syncCommentStates()
        }
    }

    func pinPostIDs(_ postIDs: Set<PostID>) {
        postStore.pin(postIDs)
        syncPostStates()
    }

    func unpinPostIDs(_ postIDs: Set<PostID>) {
        postStore.unpin(postIDs)
        syncPostStates()
    }

    func pinCommentIDs(_ commentIDs: Set<CommentID>) {
        commentStore.pin(commentIDs)
        syncCommentStates()
    }

    func unpinCommentIDs(_ commentIDs: Set<CommentID>) {
        commentStore.unpin(commentIDs)
        syncCommentStates()
    }

    func hideCommentIDs(_ commentIDs: Set<CommentID>) {
        commentStore.hide(commentIDs)
        syncCommentStates()
    }

    func invalidateRepresentativeComment(for postID: PostID) {
        for (targetPostID, continuation) in representativeCommentInvalidationContinuations.values where targetPostID == postID {
            continuation.yield(postID)
        }
    }

    func seedCommentLikeStates(
        comments: [Comment],
        userStates: [CommentID: CommentUserState],
        userID: UserID
    ) {
        commentStore.seedLikeStates(
            comments: comments,
            userStates: userStates,
            userID: userID
        )
        syncCommentStates()
    }

    func applyOptimisticCommentLike(
        comment: Comment,
        userID: UserID,
        isLiked: Bool,
        baseLiked: Bool? = nil,
        baseLikeCount: Int? = nil
    ) {
        commentStore.applyOptimisticLike(
            comment: comment,
            userID: userID,
            isLiked: isLiked,
            baseLiked: baseLiked,
            baseLikeCount: baseLikeCount
        )
        syncCommentStates()
    }

    func applyCommentLikeResult(_ result: CommentEngagementResult) {
        commentStore.applyLikeResult(result)
        syncCommentStates()
    }

    func restoreCommentLike(
        comment: Comment,
        userID: UserID,
        isLiked: Bool,
        likeCount: Int
    ) {
        commentStore.restoreLike(
            comment: comment,
            userID: userID,
            isLiked: isLiked,
            likeCount: likeCount
        )
        syncCommentStates()
    }

    func seed(
        post: LookbookPost,
        visibleCommentCount: Int?,
        userState: PostUserState?
    ) {
        postStore.seed(
            post: post,
            visibleCommentCount: visibleCommentCount,
            userState: userState
        )
        syncPostStates()
    }

    func seedPostMetrics(_ post: LookbookPost) {
        postStore.seedPostMetrics(post)
        syncPostStates()
    }

    func applyOptimisticLike(
        postID: PostID,
        userID: UserID,
        isLiked: Bool,
        baseLiked: Bool? = nil,
        baseLikeCount: Int? = nil
    ) {
        postStore.applyOptimisticLike(
            postID: postID,
            userID: userID,
            isLiked: isLiked,
            baseLiked: baseLiked,
            baseLikeCount: baseLikeCount
        )
        syncPostStates()
    }

    func applyOptimisticSave(
        postID: PostID,
        userID: UserID,
        isSaved: Bool,
        baseSaved: Bool? = nil,
        baseSaveCount: Int? = nil
    ) {
        postStore.applyOptimisticSave(
            postID: postID,
            userID: userID,
            isSaved: isSaved,
            baseSaved: baseSaved,
            baseSaveCount: baseSaveCount
        )
        syncPostStates()
    }

    func applyLikeResult(
        _ result: PostEngagementResult,
        shouldApplySave: Bool
    ) {
        postStore.applyLikeResult(
            result,
            shouldApplySave: shouldApplySave
        )
        syncPostStates()
    }

    func applySaveResult(
        _ result: PostEngagementResult,
        shouldApplyLike: Bool
    ) {
        postStore.applySaveResult(
            result,
            shouldApplyLike: shouldApplyLike
        )
        syncPostStates()
    }

    func restoreLike(
        postID: PostID,
        userID: UserID,
        isLiked: Bool,
        likeCount: Int?
    ) {
        postStore.restoreLike(
            postID: postID,
            userID: userID,
            isLiked: isLiked,
            likeCount: likeCount
        )
        syncPostStates()
    }

    func restoreSave(
        postID: PostID,
        userID: UserID,
        isSaved: Bool,
        saveCount: Int?
    ) {
        postStore.restoreSave(
            postID: postID,
            userID: userID,
            isSaved: isSaved,
            saveCount: saveCount
        )
        syncPostStates()
    }

    func applyCommentMutation(_ result: CommentMutationResult) {
        postStore.applyCommentMutation(result)
        if let parentCommentID = result.parentCommentID {
            commentStore.applyReplyCount(result.replyCount, for: parentCommentID)
        }
        syncPostStates()
        syncCommentStates()
    }

    func applyCommentDeletion(_ result: CommentDeletionResult) {
        postStore.applyCommentDeletion(result)
        commentStore.hide(result.commentID)
        if let parentCommentID = result.parentCommentID {
            commentStore.applyReplyCount(result.replyCount, for: parentCommentID)
        }
        syncPostStates()
        syncCommentStates()
    }

    private func syncPostStates() {
        let previousStates = postStates
        let nextStates = postStore.states
        postStates = nextStates
        notifyPostStateInvalidations(previousStates: previousStates, nextStates: nextStates)
    }

    private func syncCommentStates() {
        let previousCommentStates = commentStates
        let nextCommentStates = commentStore.states
        commentStates = nextCommentStates
        notifyCommentStateInvalidations(previousStates: previousCommentStates, nextStates: nextCommentStates)
    }

    private func notifyPostStateInvalidations(
        previousStates: [PostID: LookbookPostInteractionState],
        nextStates: [PostID: LookbookPostInteractionState]
    ) {
        let changedPostIDs = Set(previousStates.keys)
            .union(nextStates.keys)
            .filter { previousStates[$0] != nextStates[$0] }

        guard changedPostIDs.isEmpty == false else { return }

        for postID in changedPostIDs {
            for (subscribedPostIDs, continuation) in postStateInvalidationContinuations.values where subscribedPostIDs.contains(postID) {
                continuation.yield(postID)
            }
        }
    }

    private func notifyCommentStateInvalidations(
        previousStates: [CommentID: CommentInteractionState],
        nextStates: [CommentID: CommentInteractionState]
    ) {
        let changedCommentIDs = Set(previousStates.keys)
            .union(nextStates.keys)
            .filter { previousStates[$0] != nextStates[$0] }

        for commentID in changedCommentIDs {
            for (subscribedCommentIDs, continuation) in commentStateInvalidationContinuations.values where subscribedCommentIDs.contains(commentID) {
                continuation.yield(commentID)
            }
        }
    }
}
