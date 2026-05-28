//
//  SeasonEngagementResult.swift
//  OutPick
//
//  Created by Codex on 5/27/26.
//

import Foundation

struct SeasonEngagementResult: Equatable {
    let brandID: BrandID
    let seasonID: SeasonID
    let userID: UserID
    let isLiked: Bool
    let likeCount: Int
}
