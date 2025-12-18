//
//  Comment.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation

struct Comment: Equatable, Codable, Identifiable {
    var id: CommentID
    var postID: PostID
    var userID: UserID
    var message: String
    var createdAt: Date
    var isDeleted: Bool
}
