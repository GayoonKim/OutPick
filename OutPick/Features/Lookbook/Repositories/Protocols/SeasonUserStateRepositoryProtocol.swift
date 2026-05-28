//
//  SeasonUserStateRepositoryProtocol.swift
//  OutPick
//
//  Created by Codex on 5/27/26.
//

import Foundation
import FirebaseFirestore

struct SeasonUserStatePage {
    let items: [SeasonUserState]
    let last: DocumentSnapshot?
}

protocol SeasonUserStateRepositoryProtocol {
    func fetchSeasonUserState(
        userID: UserID,
        brandID: BrandID,
        seasonID: SeasonID
    ) async throws -> SeasonUserState?

    func fetchLikedSeasonUserStates(
        userID: UserID,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> SeasonUserStatePage
}
