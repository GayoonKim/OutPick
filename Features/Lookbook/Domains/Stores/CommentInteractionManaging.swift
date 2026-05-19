//
//  CommentInteractionManaging.swift
//  OutPick
//
//  Created by Codex on 5/19/26.
//

import Foundation

@MainActor
protocol CommentInteractionManaging: AnyObject {
    func replyCount(for comment: Comment) -> Int
    func likeCount(for comment: Comment) -> Int
    func isCommentLiked(_ comment: Comment, userID: UserID?) -> Bool
    func isCommentHidden(_ commentID: CommentID) -> Bool
    func commentState(for commentID: CommentID) -> CommentInteractionState?
    func commentStateInvalidationStream(for commentIDs: Set<CommentID>) -> AsyncStream<CommentID>
    func representativeCommentInvalidationStream(for postID: PostID) -> AsyncStream<PostID>
    func pinScope(postIDs: Set<PostID>, commentIDs: Set<CommentID>) -> InteractionPinScope
    func hideCommentIDs(_ commentIDs: Set<CommentID>)
    func invalidateRepresentativeComment(for postID: PostID)
    func seedCommentLikeStates(
        comments: [Comment],
        userStates: [CommentID: CommentUserState],
        userID: UserID
    )
    func applyOptimisticCommentLike(
        comment: Comment,
        userID: UserID,
        isLiked: Bool,
        baseLiked: Bool?,
        baseLikeCount: Int?
    )
    func applyCommentLikeResult(_ result: CommentEngagementResult)
    func restoreCommentLike(comment: Comment, userID: UserID, isLiked: Bool, likeCount: Int)
    func applyCommentMutation(_ result: CommentMutationResult)
    func applyCommentDeletion(_ result: CommentDeletionResult)
}
