//
//  BrandUserState.swift
//  OutPick
//
//  Created by Codex on 5/25/26.
//

import Foundation

struct BrandUserState: Equatable, Codable {
    var brandID: BrandID
    var userID: UserID
    var isLiked: Bool
    var updatedAt: Date
}
