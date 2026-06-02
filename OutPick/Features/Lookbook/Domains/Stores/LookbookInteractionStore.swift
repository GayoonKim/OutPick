//
//  LookbookInteractionStore.swift
//  OutPick
//
//  Created by Codex on 5/7/26.
//

import Foundation

@MainActor
final class LookbookInteractionStore: PostInteractionManaging, CommentInteractionManaging, BrandInteractionManaging, SeasonInteractionManaging {
    private var postStates: [PostInteractionKey: LookbookPostInteractionState] = [:]
    private var postStore: PostInteractionStore
    private var commentStore: CommentInteractionStore
    private var brandStore: BrandInteractionStore
    private var seasonStore: SeasonInteractionStore
    private var commentStates: [CommentID: CommentInteractionState] = [:]
    private var brandStates: [BrandID: BrandInteractionState] = [:]
    private var seasonStates: [SeasonInteractionKey: SeasonInteractionState] = [:]
    private var postStateInvalidationContinuations: [UUID: (keys: Set<PostInteractionKey>, continuation: AsyncStream<PostInteractionKey>.Continuation)] = [:]
    private var allPostStateInvalidationContinuations: [UUID: AsyncStream<PostInteractionKey>.Continuation] = [:]
    private var commentStateInvalidationContinuations: [UUID: (commentIDs: Set<CommentID>, continuation: AsyncStream<CommentID>.Continuation)] = [:]
    private var brandStateInvalidationContinuations: [UUID: (brandIDs: Set<BrandID>, continuation: AsyncStream<BrandID>.Continuation)] = [:]
    private var allBrandStateInvalidationContinuations: [UUID: AsyncStream<BrandID>.Continuation] = [:]
    private var seasonStateInvalidationContinuations: [UUID: (keys: Set<SeasonInteractionKey>, continuation: AsyncStream<SeasonInteractionKey>.Continuation)] = [:]
    private var allSeasonStateInvalidationContinuations: [UUID: AsyncStream<SeasonInteractionKey>.Continuation] = [:]
    private var representativeCommentInvalidationContinuations: [UUID: (postID: PostID, continuation: AsyncStream<PostID>.Continuation)] = [:]

    init(
        maxPostStateCount: Int = 300,
        maxCommentStateCount: Int = 600,
        maxBrandStateCount: Int = 300,
        maxSeasonStateCount: Int = 300,
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
        self.brandStore = BrandInteractionStore(
            maxBrandStateCount: maxBrandStateCount,
            stateRetentionInterval: stateRetentionInterval
        )
        self.seasonStore = SeasonInteractionStore(
            maxSeasonStateCount: maxSeasonStateCount,
            stateRetentionInterval: stateRetentionInterval
        )
    }

    func state(for key: PostInteractionKey) -> LookbookPostInteractionState? {
        postStore.state(for: key)
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
        for keys: Set<PostInteractionKey>
    ) -> AsyncStream<PostInteractionKey> {
        guard keys.isEmpty == false else {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }

        return AsyncStream { [weak self] continuation in
            guard let self else { return }
            let continuationID = UUID()
            self.postStateInvalidationContinuations[continuationID] = (keys, continuation)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.postStateInvalidationContinuations.removeValue(forKey: continuationID)
                }
            }
        }
    }

    func allPostStateInvalidationStream() -> AsyncStream<PostInteractionKey> {
        AsyncStream { [weak self] continuation in
            guard let self else { return }
            let continuationID = UUID()
            self.allPostStateInvalidationContinuations[continuationID] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.allPostStateInvalidationContinuations.removeValue(forKey: continuationID)
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

    func brandState(for brandID: BrandID) -> BrandInteractionState? {
        brandStore.state(for: brandID)
    }

    func seasonState(for key: SeasonInteractionKey) -> SeasonInteractionState? {
        seasonStore.state(for: key)
    }

    func brandStateInvalidationStream(
        for brandIDs: Set<BrandID>
    ) -> AsyncStream<BrandID> {
        guard brandIDs.isEmpty == false else {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }

        return AsyncStream { [weak self] continuation in
            guard let self else { return }
            let continuationID = UUID()
            self.brandStateInvalidationContinuations[continuationID] = (brandIDs, continuation)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.brandStateInvalidationContinuations.removeValue(forKey: continuationID)
                }
            }
        }
    }

    func allBrandStateInvalidationStream() -> AsyncStream<BrandID> {
        AsyncStream { [weak self] continuation in
            guard let self else { return }
            let continuationID = UUID()
            self.allBrandStateInvalidationContinuations[continuationID] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.allBrandStateInvalidationContinuations.removeValue(forKey: continuationID)
                }
            }
        }
    }

    func seasonStateInvalidationStream(
        for keys: Set<SeasonInteractionKey>
    ) -> AsyncStream<SeasonInteractionKey> {
        guard keys.isEmpty == false else {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }

        return AsyncStream { [weak self] continuation in
            guard let self else { return }
            let continuationID = UUID()
            self.seasonStateInvalidationContinuations[continuationID] = (keys, continuation)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.seasonStateInvalidationContinuations.removeValue(forKey: continuationID)
                }
            }
        }
    }

    func allSeasonStateInvalidationStream() -> AsyncStream<SeasonInteractionKey> {
        AsyncStream { [weak self] continuation in
            guard let self else { return }
            let continuationID = UUID()
            self.allSeasonStateInvalidationContinuations[continuationID] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.allSeasonStateInvalidationContinuations.removeValue(forKey: continuationID)
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
        postKeys: Set<PostInteractionKey>,
        commentIDs: Set<CommentID>
    ) -> InteractionPinScope {
        if postKeys.isEmpty == false {
            postStore.pin(postKeys)
        }
        if commentIDs.isEmpty == false {
            commentStore.pin(commentIDs)
        }
        syncPostStates()
        syncCommentStates()

        return InteractionPinScope { [weak self] in
            guard let self else { return }
            if postKeys.isEmpty == false {
                self.postStore.unpin(postKeys)
            }
            if commentIDs.isEmpty == false {
                self.commentStore.unpin(commentIDs)
            }
            self.syncPostStates()
            self.syncCommentStates()
        }
    }

    func pinScope(
        postIDs: Set<PostID> = [],
        commentIDs: Set<CommentID> = []
    ) -> InteractionPinScope {
        if commentIDs.isEmpty == false {
            commentStore.pin(commentIDs)
        }
        syncCommentStates()

        return InteractionPinScope { [weak self] in
            guard let self else { return }
            if commentIDs.isEmpty == false {
                self.commentStore.unpin(commentIDs)
            }
            self.syncCommentStates()
        }
    }

    func pinPostKeys(_ postKeys: Set<PostInteractionKey>) {
        postStore.pin(postKeys)
        syncPostStates()
    }

    func unpinPostKeys(_ postKeys: Set<PostInteractionKey>) {
        postStore.unpin(postKeys)
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

    func seedBrand(_ brand: Brand, userState: BrandUserState?) {
        brandStore.seed(
            brand: brand,
            userState: userState
        )
        syncBrandStates()
    }

    func seedSeason(_ season: Season, userState: SeasonUserState?) {
        seasonStore.seed(
            season: season,
            userState: userState
        )
        syncSeasonStates()
    }

    func seedPostMetrics(_ post: LookbookPost) {
        postStore.seedPostMetrics(post)
        syncPostStates()
    }

    func applyOptimisticLike(
        key: PostInteractionKey,
        userID: UserID,
        isLiked: Bool,
        baseLiked: Bool? = nil,
        baseLikeCount: Int? = nil
    ) {
        postStore.applyOptimisticLike(
            key: key,
            userID: userID,
            isLiked: isLiked,
            baseLiked: baseLiked,
            baseLikeCount: baseLikeCount
        )
        syncPostStates()
    }

    func applyOptimisticSave(
        key: PostInteractionKey,
        userID: UserID,
        isSaved: Bool,
        baseSaved: Bool? = nil,
        baseSaveCount: Int? = nil
    ) {
        postStore.applyOptimisticSave(
            key: key,
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
        key: PostInteractionKey,
        userID: UserID,
        isLiked: Bool,
        likeCount: Int?
    ) {
        postStore.restoreLike(
            key: key,
            userID: userID,
            isLiked: isLiked,
            likeCount: likeCount
        )
        syncPostStates()
    }

    func restoreSave(
        key: PostInteractionKey,
        userID: UserID,
        isSaved: Bool,
        saveCount: Int?
    ) {
        postStore.restoreSave(
            key: key,
            userID: userID,
            isSaved: isSaved,
            saveCount: saveCount
        )
        syncPostStates()
    }

    func applyOptimisticBrandLike(
        brandID: BrandID,
        userID: UserID,
        isLiked: Bool,
        baseLiked: Bool? = nil,
        baseLikeCount: Int? = nil
    ) {
        brandStore.applyOptimisticLike(
            brandID: brandID,
            userID: userID,
            isLiked: isLiked,
            baseLiked: baseLiked,
            baseLikeCount: baseLikeCount
        )
        syncBrandStates()
    }

    func applyBrandLikeResult(_ result: BrandEngagementResult) {
        brandStore.applyLikeResult(result)
        syncBrandStates()
    }

    func setBrandLikeMutationState(
        brandID: BrandID,
        isMutating: Bool
    ) {
        brandStore.setLikeMutationState(
            brandID: brandID,
            isMutating: isMutating
        )
        syncBrandStates()
    }

    func restoreBrandLike(
        brandID: BrandID,
        userID: UserID,
        isLiked: Bool,
        likeCount: Int?
    ) {
        brandStore.restoreLike(
            brandID: brandID,
            userID: userID,
            isLiked: isLiked,
            likeCount: likeCount
        )
        syncBrandStates()
    }

    func applyOptimisticSeasonLike(
        season: Season,
        userID: UserID,
        isLiked: Bool,
        baseLiked: Bool? = nil,
        baseLikeCount: Int? = nil
    ) {
        seasonStore.applyOptimisticLike(
            season: season,
            userID: userID,
            isLiked: isLiked,
            baseLiked: baseLiked,
            baseLikeCount: baseLikeCount
        )
        syncSeasonStates()
    }

    func applySeasonLikeResult(_ result: SeasonEngagementResult) {
        seasonStore.applyLikeResult(result)
        syncSeasonStates()
    }

    func setSeasonLikeMutationState(
        key: SeasonInteractionKey,
        isMutating: Bool
    ) {
        seasonStore.setLikeMutationState(
            key: key,
            isMutating: isMutating
        )
        syncSeasonStates()
    }

    func restoreSeasonLike(
        season: Season,
        userID: UserID,
        isLiked: Bool,
        likeCount: Int?
    ) {
        seasonStore.restoreLike(
            season: season,
            userID: userID,
            isLiked: isLiked,
            likeCount: likeCount
        )
        syncSeasonStates()
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

    private func syncBrandStates() {
        let previousStates = brandStates
        let nextStates = brandStore.states
        brandStates = nextStates
        notifyBrandStateInvalidations(previousStates: previousStates, nextStates: nextStates)
    }

    private func syncSeasonStates() {
        let previousStates = seasonStates
        let nextStates = seasonStore.states
        seasonStates = nextStates
        notifySeasonStateInvalidations(previousStates: previousStates, nextStates: nextStates)
    }

    private func notifyPostStateInvalidations(
        previousStates: [PostInteractionKey: LookbookPostInteractionState],
        nextStates: [PostInteractionKey: LookbookPostInteractionState]
    ) {
        let changedKeys = Set(previousStates.keys)
            .union(nextStates.keys)
            .filter { previousStates[$0] != nextStates[$0] }

        guard changedKeys.isEmpty == false else { return }

        for key in changedKeys {
            for (subscribedKeys, continuation) in postStateInvalidationContinuations.values where subscribedKeys.contains(key) {
                continuation.yield(key)
            }
            for continuation in allPostStateInvalidationContinuations.values {
                continuation.yield(key)
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

    private func notifyBrandStateInvalidations(
        previousStates: [BrandID: BrandInteractionState],
        nextStates: [BrandID: BrandInteractionState]
    ) {
        let changedBrandIDs = Set(previousStates.keys)
            .union(nextStates.keys)
            .filter { previousStates[$0] != nextStates[$0] }

        guard changedBrandIDs.isEmpty == false else { return }

        for brandID in changedBrandIDs {
            for (subscribedBrandIDs, continuation) in brandStateInvalidationContinuations.values where subscribedBrandIDs.contains(brandID) {
                continuation.yield(brandID)
            }
            for continuation in allBrandStateInvalidationContinuations.values {
                continuation.yield(brandID)
            }
        }
    }

    private func notifySeasonStateInvalidations(
        previousStates: [SeasonInteractionKey: SeasonInteractionState],
        nextStates: [SeasonInteractionKey: SeasonInteractionState]
    ) {
        let changedKeys = Set(previousStates.keys)
            .union(nextStates.keys)
            .filter { previousStates[$0] != nextStates[$0] }

        guard changedKeys.isEmpty == false else { return }

        for key in changedKeys {
            for (subscribedKeys, continuation) in seasonStateInvalidationContinuations.values where subscribedKeys.contains(key) {
                continuation.yield(key)
            }
            for continuation in allSeasonStateInvalidationContinuations.values {
                continuation.yield(key)
            }
        }
    }
}
