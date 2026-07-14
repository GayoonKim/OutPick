//
//  BrandUserStateDTO.swift
//  OutPick
//
//  Created by Codex on 5/25/26.
//

import Foundation
import FirebaseFirestore

struct BrandUserStateDTO: Decodable {
    let brandID: String?
    let userID: String?
    let isLiked: Bool?
    let likedAt: Timestamp?
    let updatedAt: Timestamp?

    func toDomain(brandID: BrandID, userID: UserID) -> BrandUserState {
        BrandUserState(
            brandID: brandID,
            userID: userID,
            isLiked: isLiked ?? true,
            updatedAt: updatedAt?.dateValue() ?? likedAt?.dateValue() ?? Date(timeIntervalSince1970: 0)
        )
    }
}
