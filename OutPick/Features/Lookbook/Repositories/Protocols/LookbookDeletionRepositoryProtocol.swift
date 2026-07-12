//
//  LookbookDeletionRepositoryProtocol.swift
//  OutPick
//
//  Created by Codex on 7/7/26.
//

import Foundation

protocol LookbookDeletionRepositoryProtocol {
    func requestBrandDeletion(
        brandID: BrandID,
        reason: String?
    ) async throws -> LookbookDeletionMutationReceipt

    func cancelBrandDeletion(
        brandID: BrandID
    ) async throws -> LookbookDeletionMutationReceipt

    func softDeleteSeason(
        brandID: BrandID,
        seasonID: SeasonID,
        reason: String?
    ) async throws -> LookbookDeletionMutationReceipt

    func batchSoftDeleteSeasons(
        brandID: BrandID,
        seasonIDs: [SeasonID],
        reason: String?
    ) async throws -> LookbookDeletionBatchResult

    func restoreSeason(
        brandID: BrandID,
        seasonID: SeasonID
    ) async throws -> LookbookDeletionMutationReceipt

    func softDeletePost(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        reason: String?
    ) async throws -> LookbookDeletionMutationReceipt

    func batchSoftDeletePosts(
        brandID: BrandID,
        seasonID: SeasonID,
        postIDs: [PostID],
        reason: String?
    ) async throws -> LookbookDeletionBatchResult

    func restorePost(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID
    ) async throws -> LookbookDeletionMutationReceipt

    func listDeletionRequests(
        targetType: LookbookDeletionTargetType?,
        brandID: BrandID?,
        limit: Int,
        cursor: LookbookDeletionRequestPage.Cursor?
    ) async throws -> LookbookDeletionRequestPage

    func retryFailedPurge(
        requestID: String
    ) async throws -> LookbookDeletionRetryReceipt
}
