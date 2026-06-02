//
//  PostInteractionManaging.swift
//  OutPick
//
//  Created by Codex on 5/19/26.
//

import Foundation

struct LookbookPostInteractionState: Equatable {
    let key: PostInteractionKey
    let postID: PostID
    var metrics: PostMetrics
    var visibleCommentCount: Int?
    var userState: PostUserState?
    var updatedAt: Date
}

struct PostInteractionKey: Hashable, Codable {
    let brandID: BrandID
    let seasonID: SeasonID
    let postID: PostID

    init(brandID: BrandID, seasonID: SeasonID, postID: PostID) {
        self.brandID = brandID
        self.seasonID = seasonID
        self.postID = postID
    }

    init(post: LookbookPost) {
        self.brandID = post.brandID
        self.seasonID = post.seasonID
        self.postID = post.id
    }
}

@MainActor
protocol PostInteractionManaging: AnyObject {
    func state(for key: PostInteractionKey) -> LookbookPostInteractionState?
    func postStateInvalidationStream(for keys: Set<PostInteractionKey>) -> AsyncStream<PostInteractionKey>
    func pinScope(postKeys: Set<PostInteractionKey>, commentIDs: Set<CommentID>) -> InteractionPinScope
    func seed(post: LookbookPost, visibleCommentCount: Int?, userState: PostUserState?)
    func seedPostMetrics(_ post: LookbookPost)
    func applyOptimisticLike(key: PostInteractionKey, userID: UserID, isLiked: Bool, baseLiked: Bool?, baseLikeCount: Int?)
    func applyOptimisticSave(key: PostInteractionKey, userID: UserID, isSaved: Bool, baseSaved: Bool?, baseSaveCount: Int?)
    func applyLikeResult(_ result: PostEngagementResult, shouldApplySave: Bool)
    func applySaveResult(_ result: PostEngagementResult, shouldApplyLike: Bool)
    func restoreLike(key: PostInteractionKey, userID: UserID, isLiked: Bool, likeCount: Int?)
    func restoreSave(key: PostInteractionKey, userID: UserID, isSaved: Bool, saveCount: Int?)
}
