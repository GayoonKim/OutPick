//
//  BrandInteractionStore.swift
//  OutPick
//
//  Created by Codex on 5/25/26.
//

import Foundation

struct BrandInteractionStore {
    private var cache: PinAwareInteractionCache<BrandID, BrandInteractionState>

    init(
        maxBrandStateCount: Int,
        stateRetentionInterval: TimeInterval
    ) {
        self.cache = PinAwareInteractionCache(
            maxCount: maxBrandStateCount,
            retentionInterval: stateRetentionInterval
        )
    }

    var states: [BrandID: BrandInteractionState] {
        cache.valuesByKey
    }

    mutating func state(for brandID: BrandID) -> BrandInteractionState? {
        cache.value(for: brandID)
    }

    mutating func seed(
        brand: Brand,
        userState: BrandUserState?
    ) {
        cache.set(
            BrandInteractionState(
                brandID: brand.id,
                brand: brand,
                metrics: brand.metrics,
                userState: userState,
                isMutatingLike: false,
                updatedAt: Date()
            ),
            for: brand.id
        )
    }

    mutating func applyOptimisticLike(
        brandID: BrandID,
        userID: UserID,
        isLiked: Bool,
        baseLiked: Bool?,
        baseLikeCount: Int?
    ) {
        cache.update(for: brandID) { state in
            let previousLiked = baseLiked ?? state.userState?.isLiked ?? false
            let currentLikeCount = baseLikeCount ?? state.metrics.likeCount
            let likeDelta = isLiked == previousLiked ? 0 : (isLiked ? 1 : -1)
            state.metrics = BrandMetrics(
                likeCount: max(0, currentLikeCount + likeDelta),
                viewCount: state.metrics.viewCount,
                popularScore: state.metrics.popularScore
            )
            state.brand = state.brand.updatingMetrics(state.metrics)
            state.userState = BrandUserState(
                brandID: brandID,
                userID: userID,
                isLiked: isLiked,
                updatedAt: Date()
            )
            state.updatedAt = Date()
        }
    }

    mutating func setLikeMutationState(
        brandID: BrandID,
        isMutating: Bool
    ) {
        cache.update(for: brandID) { state in
            state.isMutatingLike = isMutating
            state.updatedAt = Date()
        }
    }

    mutating func applyLikeResult(_ result: BrandEngagementResult) {
        cache.update(for: result.brandID) { state in
            state.metrics = BrandMetrics(
                likeCount: max(0, result.likeCount),
                viewCount: state.metrics.viewCount,
                popularScore: state.metrics.popularScore
            )
            state.brand = state.brand.updatingMetrics(state.metrics)
            state.userState = BrandUserState(
                brandID: result.brandID,
                userID: result.userID,
                isLiked: result.isLiked,
                updatedAt: Date()
            )
            state.updatedAt = Date()
        }
    }

    mutating func restoreLike(
        brandID: BrandID,
        userID: UserID,
        isLiked: Bool,
        likeCount: Int?
    ) {
        cache.update(for: brandID) { state in
            if let likeCount {
                state.metrics = BrandMetrics(
                    likeCount: max(0, likeCount),
                    viewCount: state.metrics.viewCount,
                    popularScore: state.metrics.popularScore
                )
                state.brand = state.brand.updatingMetrics(state.metrics)
            }
            state.userState = BrandUserState(
                brandID: brandID,
                userID: userID,
                isLiked: isLiked,
                updatedAt: Date()
            )
            state.updatedAt = Date()
        }
    }
}

private extension Brand {
    func updatingMetrics(_ metrics: BrandMetrics) -> Brand {
        Brand(
            id: id,
            name: name,
            englishName: englishName,
            websiteURL: websiteURL,
            lookbookArchiveURL: lookbookArchiveURL,
            logoThumbPath: logoThumbPath,
            logoDetailPath: logoDetailPath,
            logoOriginalPath: logoOriginalPath,
            isFeatured: isFeatured,
            discoveryStatus: discoveryStatus,
            lastDiscoveryErrorMessage: lastDiscoveryErrorMessage,
            lastDiscoveryRequestedAt: lastDiscoveryRequestedAt,
            lastDiscoveryCompletedAt: lastDiscoveryCompletedAt,
            metrics: metrics,
            updatedAt: updatedAt
        )
    }
}
