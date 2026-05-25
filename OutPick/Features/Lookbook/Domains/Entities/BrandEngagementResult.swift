//
//  BrandEngagementResult.swift
//  OutPick
//
//  Created by Codex on 5/25/26.
//

import Foundation

struct BrandEngagementResult: Equatable {
    let brandID: BrandID
    let userID: UserID
    let isLiked: Bool
    let likeCount: Int
}
