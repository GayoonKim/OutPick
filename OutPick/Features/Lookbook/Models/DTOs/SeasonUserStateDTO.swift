//
//  SeasonUserStateDTO.swift
//  OutPick
//
//  Created by Codex on 5/27/26.
//

import Foundation
import FirebaseFirestore

struct SeasonUserStateDTO: Codable {
    @DocumentID var id: String?

    let brandID: String?
    let seasonID: String?
    let userID: String?
    let isLiked: Bool?
    let likedAt: Timestamp?
    let updatedAt: Timestamp?

    func toDomain(
        brandID: BrandID,
        seasonID: SeasonID,
        userID: UserID
    ) -> SeasonUserState {
        SeasonUserState(
            brandID: brandID,
            seasonID: seasonID,
            userID: userID,
            isLiked: isLiked ?? true,
            updatedAt: updatedAt?.dateValue() ?? likedAt?.dateValue() ?? Date(timeIntervalSince1970: 0)
        )
    }
}
