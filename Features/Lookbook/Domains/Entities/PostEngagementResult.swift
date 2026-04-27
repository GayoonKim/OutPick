//
//  PostEngagementResult.swift
//  OutPick
//
//  Created by Codex on 4/28/26.
//

import Foundation

struct PostEngagementResult: Equatable {
    let postID: PostID
    let userID: UserID
    let isLiked: Bool
    let isSaved: Bool
    let metrics: PostMetrics
}
