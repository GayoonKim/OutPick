//
//  SeasonInteractionManaging.swift
//  OutPick
//
//  Created by Codex on 5/28/26.
//

import Foundation

struct SeasonInteractionKey: Hashable {
    let brandID: BrandID
    let seasonID: SeasonID

    init(brandID: BrandID, seasonID: SeasonID) {
        self.brandID = brandID
        self.seasonID = seasonID
    }
}

struct SeasonInteractionState: Equatable {
    let key: SeasonInteractionKey
    var season: Season
    var userState: SeasonUserState?
    var isMutatingLike: Bool
    var updatedAt: Date
}

@MainActor
protocol SeasonInteractionManaging: AnyObject {
    func seasonState(for key: SeasonInteractionKey) -> SeasonInteractionState?
    func seasonStateInvalidationStream(for keys: Set<SeasonInteractionKey>) -> AsyncStream<SeasonInteractionKey>
    func allSeasonStateInvalidationStream() -> AsyncStream<SeasonInteractionKey>
    func seedSeason(_ season: Season, userState: SeasonUserState?)
    func applyOptimisticSeasonLike(
        season: Season,
        userID: UserID,
        isLiked: Bool,
        baseLiked: Bool?,
        baseLikeCount: Int?
    )
    func applySeasonLikeResult(_ result: SeasonEngagementResult)
    func setSeasonLikeMutationState(
        key: SeasonInteractionKey,
        isMutating: Bool
    )
    func restoreSeasonLike(
        season: Season,
        userID: UserID,
        isLiked: Bool,
        likeCount: Int?
    )
}
