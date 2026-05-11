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

final class InteractionPinScope {
    private var invalidateAction: (@MainActor () -> Void)?

    init(invalidateAction: @escaping @MainActor () -> Void) {
        self.invalidateAction = invalidateAction
    }

    @MainActor
    func invalidate() {
        guard let invalidateAction else { return }
        self.invalidateAction = nil
        invalidateAction()
    }

    deinit {
        guard let invalidateAction else { return }
        Task { @MainActor in
            invalidateAction()
        }
    }
}

@MainActor
final class LookbookInteractionStore: ObservableObject {
    @Published private(set) var postStates: [PostID: LookbookPostInteractionState] = [:]
    @Published private var replyCounts: [CommentID: Int] = [:]

    private var postStore: PostInteractionStore
    private var commentStore: CommentInteractionStore
    private var commentStates: [CommentID: CommentInteractionState] = [:]
    private var postStateSubjects: [PostID: CurrentValueSubject<LookbookPostInteractionState?, Never>] = [:]
    private var commentStateSubjects: [CommentID: CurrentValueSubject<CommentInteractionState?, Never>] = [:]
    private var replyCountSubjects: [CommentID: CurrentValueSubject<Int?, Never>] = [:]

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

    func isCommentHidden(_ commentID: CommentID) -> Bool {
        commentStore.isHidden(commentID)
    }

    func postStatePublisher(for postID: PostID) -> AnyPublisher<LookbookPostInteractionState?, Never> {
        postStateSubject(for: postID)
            .eraseToAnyPublisher()
    }

    func commentStatePublisher(for commentID: CommentID) -> AnyPublisher<CommentInteractionState?, Never> {
        commentStateSubject(for: commentID)
            .eraseToAnyPublisher()
    }

    func replyCountPublisher(for commentID: CommentID) -> AnyPublisher<Int?, Never> {
        replyCountSubject(for: commentID)
            .eraseToAnyPublisher()
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
        publishPostStateChanges(previousStates: previousStates, nextStates: nextStates)
    }

    private func syncCommentStates() {
        let previousCommentStates = commentStates
        let nextCommentStates = commentStore.states
        commentStates = nextCommentStates
        publishCommentStateChanges(previousStates: previousCommentStates, nextStates: nextCommentStates)

        let previousReplyCounts = replyCounts
        let nextReplyCounts = commentStore.replyCounts
        replyCounts = nextReplyCounts
        publishReplyCountChanges(previousReplyCounts: previousReplyCounts, nextReplyCounts: nextReplyCounts)
    }

    private func postStateSubject(
        for postID: PostID
    ) -> CurrentValueSubject<LookbookPostInteractionState?, Never> {
        if let subject = postStateSubjects[postID] {
            return subject
        }

        let subject = CurrentValueSubject<LookbookPostInteractionState?, Never>(
            postStore.state(for: postID)
        )
        postStateSubjects[postID] = subject
        return subject
    }

    private func commentStateSubject(
        for commentID: CommentID
    ) -> CurrentValueSubject<CommentInteractionState?, Never> {
        if let subject = commentStateSubjects[commentID] {
            return subject
        }

        let subject = CurrentValueSubject<CommentInteractionState?, Never>(
            commentStore.state(for: commentID)
        )
        commentStateSubjects[commentID] = subject
        return subject
    }

    private func replyCountSubject(
        for commentID: CommentID
    ) -> CurrentValueSubject<Int?, Never> {
        if let subject = replyCountSubjects[commentID] {
            return subject
        }

        let subject = CurrentValueSubject<Int?, Never>(
            replyCounts[commentID]
        )
        replyCountSubjects[commentID] = subject
        return subject
    }

    private func publishPostStateChanges(
        previousStates: [PostID: LookbookPostInteractionState],
        nextStates: [PostID: LookbookPostInteractionState]
    ) {
        let changedPostIDs = Set(previousStates.keys)
            .union(nextStates.keys)
            .filter { previousStates[$0] != nextStates[$0] }

        for postID in changedPostIDs {
            postStateSubjects[postID]?.send(nextStates[postID])
        }
    }

    private func publishCommentStateChanges(
        previousStates: [CommentID: CommentInteractionState],
        nextStates: [CommentID: CommentInteractionState]
    ) {
        let changedCommentIDs = Set(previousStates.keys)
            .union(nextStates.keys)
            .filter { previousStates[$0] != nextStates[$0] }

        for commentID in changedCommentIDs {
            commentStateSubjects[commentID]?.send(nextStates[commentID])
        }
    }

    private func publishReplyCountChanges(
        previousReplyCounts: [CommentID: Int],
        nextReplyCounts: [CommentID: Int]
    ) {
        let changedCommentIDs = Set(previousReplyCounts.keys)
            .union(nextReplyCounts.keys)
            .filter { previousReplyCounts[$0] != nextReplyCounts[$0] }

        for commentID in changedCommentIDs {
            replyCountSubjects[commentID]?.send(nextReplyCounts[commentID])
        }
    }
}
