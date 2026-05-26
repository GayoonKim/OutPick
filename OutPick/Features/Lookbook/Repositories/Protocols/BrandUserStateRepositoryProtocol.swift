//
//  BrandUserStateRepositoryProtocol.swift
//  OutPick
//
//  Created by Codex on 5/25/26.
//

import Foundation
import FirebaseFirestore

struct BrandUserStatePage {
    let items: [BrandUserState]
    let last: DocumentSnapshot?
}

protocol BrandUserStateRepositoryProtocol {
    func fetchBrandUserState(
        userID: UserID,
        brandID: BrandID
    ) async throws -> BrandUserState?

    func fetchLikedBrandUserStates(
        userID: UserID,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> BrandUserStatePage
}
