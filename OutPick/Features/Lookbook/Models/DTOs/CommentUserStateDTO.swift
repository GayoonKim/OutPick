//
//  CommentUserStateDTO.swift
//  OutPick
//
//  Created by Codex on 5/14/26.
//

import Foundation
import FirebaseFirestore

struct CommentUserStateDTO: Decodable {
    let commentID: String?
    let userID: String?
    let isLiked: Bool?
    let updatedAt: Timestamp?

    func toDomain(commentID: CommentID, userID: UserID) -> CommentUserState {
        CommentUserState(
            commentID: commentID,
            userID: userID,
            isLiked: isLiked ?? false,
            updatedAt: updatedAt?.dateValue() ?? Date(timeIntervalSince1970: 0)
        )
    }
}
