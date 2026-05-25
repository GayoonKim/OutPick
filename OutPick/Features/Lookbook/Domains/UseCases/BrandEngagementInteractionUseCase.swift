//
//  BrandEngagementInteractionUseCase.swift
//  OutPick
//
//  Created by Codex on 5/25/26.
//

import Foundation

struct BrandEngagementInteractionInput {
    let brandID: BrandID
    let userID: UserID
    let currentUserState: BrandUserState?
    let currentMetrics: BrandMetrics?
}

struct BrandEngagementInteractionOutcome {
    let errorMessage: String?
}

@MainActor
final class BrandEngagementInteractionUseCase {
    private let repository: any BrandEngagementRepositoryProtocol
    private let brandInteractionStore: any BrandInteractionManaging
    private let debugFailureInjectionStore: LookbookDebugFailureInjectionStore?

    private var pendingLikeTarget: Bool?
    private var confirmedLikeState: Bool?
    private var confirmedLikeCount: Int?
    private(set) var isMutatingLike: Bool = false

    init(
        repository: any BrandEngagementRepositoryProtocol,
        brandInteractionStore: any BrandInteractionManaging,
        debugFailureInjectionStore: LookbookDebugFailureInjectionStore? = nil
    ) {
        self.repository = repository
        self.brandInteractionStore = brandInteractionStore
        self.debugFailureInjectionStore = debugFailureInjectionStore
    }

    func toggleLike(
        input: BrandEngagementInteractionInput
    ) async -> BrandEngagementInteractionOutcome {
        let targetState = !(input.currentUserState?.isLiked ?? false)
        if isMutatingLike == false {
            confirmedLikeState = input.currentUserState?.isLiked ?? false
            confirmedLikeCount = input.currentMetrics?.likeCount ?? 0
        }

        applyOptimisticLike(
            targetState,
            input: input
        )
        pendingLikeTarget = targetState

        guard isMutatingLike == false else {
            return BrandEngagementInteractionOutcome(errorMessage: nil)
        }

        return await drainLikeQueue(input: input)
    }

    private func drainLikeQueue(
        input: BrandEngagementInteractionInput
    ) async -> BrandEngagementInteractionOutcome {
        isMutatingLike = true
        brandInteractionStore.setBrandLikeMutationState(
            brandID: input.brandID,
            isMutating: true
        )
        defer {
            isMutatingLike = false
            confirmedLikeState = nil
            confirmedLikeCount = nil
            brandInteractionStore.setBrandLikeMutationState(
                brandID: input.brandID,
                isMutating: false
            )
        }

        while let target = pendingLikeTarget {
            pendingLikeTarget = nil

            do {
                try debugFailureInjectionStore?.throwIfNeeded(.toggleBrandLike)
                let result = try await repository.setLike(
                    brandID: input.brandID,
                    isLiked: target
                )
                confirmedLikeState = result.isLiked
                confirmedLikeCount = result.likeCount

                if let pendingLikeTarget,
                   pendingLikeTarget != result.isLiked {
                    applyOptimisticLike(
                        pendingLikeTarget,
                        input: input,
                        baseLiked: result.isLiked,
                        baseLikeCount: result.likeCount
                    )
                    continue
                }

                pendingLikeTarget = nil
                brandInteractionStore.applyBrandLikeResult(result)
            } catch {
                pendingLikeTarget = nil
                restoreConfirmedLike(input: input)
                return BrandEngagementInteractionOutcome(
                    errorMessage: "좋아요를 반영하지 못했어요."
                )
            }
        }

        return BrandEngagementInteractionOutcome(errorMessage: nil)
    }

    private func applyOptimisticLike(
        _ isLiked: Bool,
        input: BrandEngagementInteractionInput,
        baseLiked: Bool? = nil,
        baseLikeCount: Int? = nil
    ) {
        let previousLiked = baseLiked ?? input.currentUserState?.isLiked ?? false
        let likeCount = baseLikeCount ?? input.currentMetrics?.likeCount ?? 0

        brandInteractionStore.applyOptimisticBrandLike(
            brandID: input.brandID,
            userID: input.userID,
            isLiked: isLiked,
            baseLiked: previousLiked,
            baseLikeCount: likeCount
        )
    }

    private func restoreConfirmedLike(input: BrandEngagementInteractionInput) {
        guard let confirmedLikeState else { return }

        brandInteractionStore.restoreBrandLike(
            brandID: input.brandID,
            userID: input.userID,
            isLiked: confirmedLikeState,
            likeCount: confirmedLikeCount
        )
    }
}
