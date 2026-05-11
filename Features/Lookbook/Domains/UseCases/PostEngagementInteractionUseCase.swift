//
//  PostEngagementInteractionUseCase.swift
//  OutPick
//
//  Created by Codex on 5/7/26.
//

import Foundation

struct PostEngagementInteractionInput {
    let brandID: BrandID
    let seasonID: SeasonID
    let postID: PostID
    let userID: UserID
    let currentUserState: PostUserState?
    let currentMetrics: PostMetrics?
}

struct PostEngagementInteractionOutcome {
    let errorMessage: String?
}

@MainActor
final class PostEngagementInteractionUseCase {
    private let repository: any PostEngagementRepositoryProtocol
    private let interactionStore: LookbookInteractionStore

    private var pendingLikeTarget: Bool?
    private var pendingSaveTarget: Bool?
    private var confirmedLikeState: Bool?
    private var confirmedLikeCount: Int?
    private var confirmedSaveState: Bool?
    private var confirmedSaveCount: Int?
    private(set) var isMutatingLike: Bool = false
    private(set) var isMutatingSave: Bool = false

    init(
        repository: any PostEngagementRepositoryProtocol,
        interactionStore: LookbookInteractionStore
    ) {
        self.repository = repository
        self.interactionStore = interactionStore
    }

    func toggleLike(
        input: PostEngagementInteractionInput,
        onMutationStateChanged: (Bool) -> Void
    ) async -> PostEngagementInteractionOutcome {
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
            return PostEngagementInteractionOutcome(errorMessage: nil)
        }

        return await drainLikeQueue(
            input: input,
            onMutationStateChanged: onMutationStateChanged
        )
    }

    func toggleSave(
        input: PostEngagementInteractionInput,
        onMutationStateChanged: (Bool) -> Void
    ) async -> PostEngagementInteractionOutcome {
        let targetState = !(input.currentUserState?.isSaved ?? false)
        if isMutatingSave == false {
            confirmedSaveState = input.currentUserState?.isSaved ?? false
            confirmedSaveCount = input.currentMetrics?.saveCount ?? 0
        }

        applyOptimisticSave(
            targetState,
            input: input
        )
        pendingSaveTarget = targetState

        guard isMutatingSave == false else {
            return PostEngagementInteractionOutcome(errorMessage: nil)
        }

        return await drainSaveQueue(
            input: input,
            onMutationStateChanged: onMutationStateChanged
        )
    }

    private func drainLikeQueue(
        input: PostEngagementInteractionInput,
        onMutationStateChanged: (Bool) -> Void
    ) async -> PostEngagementInteractionOutcome {
        isMutatingLike = true
        onMutationStateChanged(true)
        defer {
            isMutatingLike = false
            confirmedLikeState = nil
            confirmedLikeCount = nil
            onMutationStateChanged(false)
        }

        while let target = pendingLikeTarget {
            pendingLikeTarget = nil

            do {
                let result = try await repository.setLike(
                    brandID: input.brandID,
                    seasonID: input.seasonID,
                    postID: input.postID,
                    isLiked: target
                )
                confirmedLikeState = result.isLiked
                confirmedLikeCount = result.metrics.likeCount

                if let pendingLikeTarget,
                   pendingLikeTarget != result.isLiked {
                    applyOptimisticLike(
                        pendingLikeTarget,
                        input: input,
                        baseLiked: result.isLiked,
                        baseLikeCount: result.metrics.likeCount
                    )
                    continue
                }

                pendingLikeTarget = nil
                applyLikeResult(result)
            } catch {
                pendingLikeTarget = nil
                restoreConfirmedLike(input: input)
                return PostEngagementInteractionOutcome(
                    errorMessage: "좋아요 상태를 변경하지 못했습니다."
                )
            }
        }

        return PostEngagementInteractionOutcome(errorMessage: nil)
    }

    private func drainSaveQueue(
        input: PostEngagementInteractionInput,
        onMutationStateChanged: (Bool) -> Void
    ) async -> PostEngagementInteractionOutcome {
        isMutatingSave = true
        onMutationStateChanged(true)
        defer {
            isMutatingSave = false
            confirmedSaveState = nil
            confirmedSaveCount = nil
            onMutationStateChanged(false)
        }

        while let target = pendingSaveTarget {
            pendingSaveTarget = nil

            do {
                let result = try await repository.setSave(
                    brandID: input.brandID,
                    seasonID: input.seasonID,
                    postID: input.postID,
                    isSaved: target
                )
                confirmedSaveState = result.isSaved
                confirmedSaveCount = result.metrics.saveCount

                if let pendingSaveTarget,
                   pendingSaveTarget != result.isSaved {
                    applyOptimisticSave(
                        pendingSaveTarget,
                        input: input,
                        baseSaved: result.isSaved,
                        baseSaveCount: result.metrics.saveCount
                    )
                    continue
                }

                pendingSaveTarget = nil
                applySaveResult(result)
            } catch {
                pendingSaveTarget = nil
                restoreConfirmedSave(input: input)
                return PostEngagementInteractionOutcome(
                    errorMessage: "저장 상태를 변경하지 못했습니다."
                )
            }
        }

        return PostEngagementInteractionOutcome(errorMessage: nil)
    }

    private func applyOptimisticLike(
        _ isLiked: Bool,
        input: PostEngagementInteractionInput,
        baseLiked: Bool? = nil,
        baseLikeCount: Int? = nil
    ) {
        let previousLiked = baseLiked ?? input.currentUserState?.isLiked ?? false
        let likeCount = baseLikeCount ?? input.currentMetrics?.likeCount ?? 0

        interactionStore.applyOptimisticLike(
            postID: input.postID,
            userID: input.userID,
            isLiked: isLiked,
            baseLiked: previousLiked,
            baseLikeCount: likeCount
        )
    }

    private func applyOptimisticSave(
        _ isSaved: Bool,
        input: PostEngagementInteractionInput,
        baseSaved: Bool? = nil,
        baseSaveCount: Int? = nil
    ) {
        let previousSaved = baseSaved ?? input.currentUserState?.isSaved ?? false
        let saveCount = baseSaveCount ?? input.currentMetrics?.saveCount ?? 0

        interactionStore.applyOptimisticSave(
            postID: input.postID,
            userID: input.userID,
            isSaved: isSaved,
            baseSaved: previousSaved,
            baseSaveCount: saveCount
        )
    }

    private func applyLikeResult(_ result: PostEngagementResult) {
        let shouldApplySave = isMutatingSave == false && pendingSaveTarget == nil
        interactionStore.applyLikeResult(result, shouldApplySave: shouldApplySave)
    }

    private func applySaveResult(_ result: PostEngagementResult) {
        let shouldApplyLike = isMutatingLike == false && pendingLikeTarget == nil
        interactionStore.applySaveResult(result, shouldApplyLike: shouldApplyLike)
    }

    private func restoreConfirmedLike(input: PostEngagementInteractionInput) {
        guard let confirmedLikeState else { return }

        interactionStore.restoreLike(
            postID: input.postID,
            userID: input.userID,
            isLiked: confirmedLikeState,
            likeCount: confirmedLikeCount
        )
    }

    private func restoreConfirmedSave(input: PostEngagementInteractionInput) {
        guard let confirmedSaveState else { return }

        interactionStore.restoreSave(
            postID: input.postID,
            userID: input.userID,
            isSaved: confirmedSaveState,
            saveCount: confirmedSaveCount
        )
    }
}
