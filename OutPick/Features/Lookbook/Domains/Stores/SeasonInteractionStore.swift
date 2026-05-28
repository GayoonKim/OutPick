//
//  SeasonInteractionStore.swift
//  OutPick
//
//  Created by Codex on 5/28/26.
//

import Foundation

struct SeasonInteractionStore {
    private var cache: PinAwareInteractionCache<SeasonInteractionKey, SeasonInteractionState>

    init(
        maxSeasonStateCount: Int,
        stateRetentionInterval: TimeInterval
    ) {
        self.cache = PinAwareInteractionCache(
            maxCount: maxSeasonStateCount,
            retentionInterval: stateRetentionInterval
        )
    }

    var states: [SeasonInteractionKey: SeasonInteractionState] {
        cache.valuesByKey
    }

    mutating func state(for key: SeasonInteractionKey) -> SeasonInteractionState? {
        cache.value(for: key)
    }

    mutating func seed(
        season: Season,
        userState: SeasonUserState?
    ) {
        let key = SeasonInteractionKey(brandID: season.brandID, seasonID: season.id)
        cache.set(
            SeasonInteractionState(
                key: key,
                season: season,
                userState: userState,
                isMutatingLike: false,
                updatedAt: Date()
            ),
            for: key
        )
    }

    mutating func applyOptimisticLike(
        season: Season,
        userID: UserID,
        isLiked: Bool,
        baseLiked: Bool?,
        baseLikeCount: Int?
    ) {
        let key = SeasonInteractionKey(brandID: season.brandID, seasonID: season.id)
        if cache.value(for: key) == nil {
            seed(season: season, userState: nil)
        }

        cache.update(for: key) { state in
            let previousLiked = baseLiked ?? state.userState?.isLiked ?? false
            let currentLikeCount = baseLikeCount ?? state.season.likeCount
            let likeDelta = isLiked == previousLiked ? 0 : (isLiked ? 1 : -1)
            state.season.likeCount = max(0, currentLikeCount + likeDelta)
            state.userState = SeasonUserState(
                brandID: season.brandID,
                seasonID: season.id,
                userID: userID,
                isLiked: isLiked,
                updatedAt: Date()
            )
            state.updatedAt = Date()
        }
    }

    mutating func setLikeMutationState(
        key: SeasonInteractionKey,
        isMutating: Bool
    ) {
        cache.update(for: key) { state in
            state.isMutatingLike = isMutating
            state.updatedAt = Date()
        }
    }

    mutating func applyLikeResult(_ result: SeasonEngagementResult) {
        let key = SeasonInteractionKey(
            brandID: result.brandID,
            seasonID: result.seasonID
        )
        cache.update(for: key) { state in
            state.season.likeCount = max(0, result.likeCount)
            state.userState = SeasonUserState(
                brandID: result.brandID,
                seasonID: result.seasonID,
                userID: result.userID,
                isLiked: result.isLiked,
                updatedAt: Date()
            )
            state.updatedAt = Date()
        }
    }

    mutating func restoreLike(
        season: Season,
        userID: UserID,
        isLiked: Bool,
        likeCount: Int?
    ) {
        let key = SeasonInteractionKey(brandID: season.brandID, seasonID: season.id)
        if cache.value(for: key) == nil {
            seed(season: season, userState: nil)
        }

        cache.update(for: key) { state in
            if let likeCount {
                state.season.likeCount = max(0, likeCount)
            }
            state.userState = SeasonUserState(
                brandID: season.brandID,
                seasonID: season.id,
                userID: userID,
                isLiked: isLiked,
                updatedAt: Date()
            )
            state.updatedAt = Date()
        }
    }
}
