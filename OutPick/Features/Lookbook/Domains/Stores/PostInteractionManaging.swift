//
//  PostInteractionManaging.swift
//  OutPick
//
//  Created by Codex on 5/19/26.
//

import Foundation

struct LookbookPostInteractionState: Equatable {
    let postID: PostID
    var metrics: PostMetrics
    var visibleCommentCount: Int?
    var userState: PostUserState?
    var updatedAt: Date
}

@MainActor
protocol PostInteractionManaging: AnyObject {
    func state(for postID: PostID) -> LookbookPostInteractionState?
    func postStateInvalidationStream(for postIDs: Set<PostID>) -> AsyncStream<PostID>
    func pinScope(postIDs: Set<PostID>, commentIDs: Set<CommentID>) -> InteractionPinScope
    func seed(post: LookbookPost, visibleCommentCount: Int?, userState: PostUserState?)
    func seedPostMetrics(_ post: LookbookPost)
    func applyOptimisticLike(postID: PostID, userID: UserID, isLiked: Bool, baseLiked: Bool?, baseLikeCount: Int?)
    func applyOptimisticSave(postID: PostID, userID: UserID, isSaved: Bool, baseSaved: Bool?, baseSaveCount: Int?)
    func applyLikeResult(_ result: PostEngagementResult, shouldApplySave: Bool)
    func applySaveResult(_ result: PostEngagementResult, shouldApplyLike: Bool)
    func restoreLike(postID: PostID, userID: UserID, isLiked: Bool, likeCount: Int?)
    func restoreSave(postID: PostID, userID: UserID, isSaved: Bool, saveCount: Int?)
}
