//
//  CommentDeletionResult.swift
//  OutPick
//
//  Created by Codex on 5/7/26.
//

import Foundation

struct CommentDeletionResult: Equatable, Codable {
    let brandID: BrandID
    let seasonID: SeasonID
    let postID: PostID
    let commentID: CommentID
    let userID: UserID
    let parentCommentID: CommentID?
    let targetType: CommentSafetyTargetType
    let deletedReplyCount: Int
    let deletedCommentCount: Int
    let commentCount: Int
    let replyCount: Int
}
