//
//  CommentDisplayItem.swift
//  OutPick
//
//  Created by Codex on 5/5/26.
//

import Foundation

struct CommentAuthorDisplay: Equatable {
    let userID: UserID
    let nickname: String
    let avatarPath: String?

    static func unknown(userID: UserID) -> CommentAuthorDisplay {
        CommentAuthorDisplay(
            userID: userID,
            nickname: "알 수 없는 사용자",
            avatarPath: nil
        )
    }
}

struct CommentDisplayItem: Identifiable, Equatable {
    let comment: Comment
    let author: CommentAuthorDisplay

    var id: CommentID {
        comment.id
    }
}
