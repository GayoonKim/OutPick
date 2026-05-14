//
//  CommentUserState.swift
//  OutPick
//
//  Created by Codex on 5/14/26.
//

import Foundation

struct CommentUserState: Equatable, Codable {
    var commentID: CommentID
    var userID: UserID
    var isLiked: Bool
    var updatedAt: Date
}
