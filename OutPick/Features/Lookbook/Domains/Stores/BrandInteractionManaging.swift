//
//  BrandInteractionManaging.swift
//  OutPick
//
//  Created by Codex on 5/25/26.
//

import Foundation

struct BrandInteractionState: Equatable {
    let brandID: BrandID
    var brand: Brand
    var metrics: BrandMetrics
    var userState: BrandUserState?
    var isMutatingLike: Bool
    var updatedAt: Date
}

@MainActor
protocol BrandInteractionManaging: AnyObject {
    func brandState(for brandID: BrandID) -> BrandInteractionState?
    func brandStateInvalidationStream(for brandIDs: Set<BrandID>) -> AsyncStream<BrandID>
    func allBrandStateInvalidationStream() -> AsyncStream<BrandID>
    func seedBrand(_ brand: Brand, userState: BrandUserState?)
    func applyOptimisticBrandLike(
        brandID: BrandID,
        userID: UserID,
        isLiked: Bool,
        baseLiked: Bool?,
        baseLikeCount: Int?
    )
    func applyBrandLikeResult(_ result: BrandEngagementResult)
    func setBrandLikeMutationState(
        brandID: BrandID,
        isMutating: Bool
    )
    func restoreBrandLike(
        brandID: BrandID,
        userID: UserID,
        isLiked: Bool,
        likeCount: Int?
    )
}
