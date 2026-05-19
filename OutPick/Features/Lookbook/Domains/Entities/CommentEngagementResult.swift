//
//  CommentEngagementResult.swift
//  OutPick
//
//  Created by Codex on 5/14/26.
//

import Foundation

struct CommentEngagementResult: Equatable {
    let brandID: BrandID
    let seasonID: SeasonID
    let postID: PostID
    let commentID: CommentID
    let userID: UserID
    let parentCommentID: CommentID?
    let isLiked: Bool
    let likeCount: Int
}
