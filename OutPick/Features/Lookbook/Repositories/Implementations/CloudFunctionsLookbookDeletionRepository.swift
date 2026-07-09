//
//  CloudFunctionsLookbookDeletionRepository.swift
//  OutPick
//
//  Created by Codex on 7/7/26.
//

import Foundation

final class CloudFunctionsLookbookDeletionRepository: LookbookDeletionRepositoryProtocol {
    private let cloudFunctionsManager: CloudFunctionsManager

    init(cloudFunctionsManager: CloudFunctionsManager = .shared) {
        self.cloudFunctionsManager = cloudFunctionsManager
    }

    func requestBrandDeletion(
        brandID: BrandID,
        reason: String?
    ) async throws -> LookbookDeletionMutationReceipt {
        try await cloudFunctionsManager.requestBrandDeletion(
            brandID: brandID.value,
            reason: reason
        )
    }

    func cancelBrandDeletion(
        brandID: BrandID
    ) async throws -> LookbookDeletionMutationReceipt {
        try await cloudFunctionsManager.cancelBrandDeletion(brandID: brandID.value)
    }

    func softDeleteSeason(
        brandID: BrandID,
        seasonID: SeasonID,
        reason: String?
    ) async throws -> LookbookDeletionMutationReceipt {
        try await cloudFunctionsManager.softDeleteSeason(
            brandID: brandID.value,
            seasonID: seasonID.value,
            reason: reason
        )
    }

    func batchSoftDeleteSeasons(
        brandID: BrandID,
        seasonIDs: [SeasonID],
        reason: String?
    ) async throws -> LookbookDeletionBatchResult {
        try await cloudFunctionsManager.batchSoftDeleteSeasons(
            brandID: brandID.value,
            seasonIDs: seasonIDs.map(\.value),
            reason: reason
        )
    }

    func restoreSeason(
        brandID: BrandID,
        seasonID: SeasonID
    ) async throws -> LookbookDeletionMutationReceipt {
        try await cloudFunctionsManager.restoreSeason(
            brandID: brandID.value,
            seasonID: seasonID.value
        )
    }

    func softDeletePost(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        reason: String?
    ) async throws -> LookbookDeletionMutationReceipt {
        try await cloudFunctionsManager.softDeletePost(
            brandID: brandID.value,
            seasonID: seasonID.value,
            postID: postID.value,
            reason: reason
        )
    }

    func batchSoftDeletePosts(
        brandID: BrandID,
        seasonID: SeasonID,
        postIDs: [PostID],
        reason: String?
    ) async throws -> LookbookDeletionBatchResult {
        try await cloudFunctionsManager.batchSoftDeletePosts(
            brandID: brandID.value,
            seasonID: seasonID.value,
            postIDs: postIDs.map(\.value),
            reason: reason
        )
    }

    func restorePost(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID
    ) async throws -> LookbookDeletionMutationReceipt {
        try await cloudFunctionsManager.restorePost(
            brandID: brandID.value,
            seasonID: seasonID.value,
            postID: postID.value
        )
    }

    func listDeletionRequests(
        statusGroup: LookbookDeletionRequestStatusGroup,
        processedScope: ProcessedRequestScope?,
        targetType: LookbookDeletionTargetType?,
        brandID: BrandID?,
        limit: Int,
        cursor: LookbookDeletionRequestPage.Cursor?
    ) async throws -> LookbookDeletionRequestPage {
        try await cloudFunctionsManager.listLookbookDeletionRequests(
            statusGroup: statusGroup,
            processedScope: processedScope,
            targetType: targetType,
            brandID: brandID,
            limit: limit,
            cursor: cursor
        )
    }
}
