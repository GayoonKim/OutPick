//
//  SeasonUserState.swift
//  OutPick
//
//  Created by Codex on 5/27/26.
//

import Foundation

struct SeasonUserState: Equatable, Codable {
    var brandID: BrandID
    var seasonID: SeasonID
    var userID: UserID
    var isLiked: Bool
    var updatedAt: Date
}
