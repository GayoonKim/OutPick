//
//  CommentMutationResult.swift
//  OutPick
//
//  Created by Codex on 5/4/26.
//

import Foundation

struct CommentMutationResult: Equatable, Codable {
    let brandID: BrandID
    let seasonID: SeasonID
    let postID: PostID
    let commentID: CommentID
    let userID: UserID
    let parentCommentID: CommentID?
    let commentCount: Int
    let replyCount: Int
}
