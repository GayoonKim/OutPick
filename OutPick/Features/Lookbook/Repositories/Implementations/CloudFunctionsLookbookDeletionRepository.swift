//
//  CloudFunctionsLookbookDeletionRepository.swift
//  OutPick
//
//  Created by Codex on 7/7/26.
//

import Foundation

final class CloudFunctionsLookbookDeletionRepository: LookbookDeletionRepositoryProtocol {
    private let transport: any CloudFunctionsTransporting

    init(transport: any CloudFunctionsTransporting = FirebaseCloudFunctionsTransport()) {
        self.transport = transport
    }

    func requestBrandDeletion(
        brandID: BrandID,
        reason: String?
    ) async throws -> LookbookDeletionMutationReceipt {
        var data: [String: Any] = ["brandID": brandID.value]
        if let reason { data["reason"] = reason }
        return try await mutation("requestBrandDeletion", data: data)
    }

    func cancelBrandDeletion(
        brandID: BrandID
    ) async throws -> LookbookDeletionMutationReceipt {
        try await mutation("cancelBrandDeletion", data: ["brandID": brandID.value])
    }

    func softDeleteSeason(
        brandID: BrandID,
        seasonID: SeasonID,
        reason: String?
    ) async throws -> LookbookDeletionMutationReceipt {
        var data: [String: Any] = ["brandID": brandID.value, "seasonID": seasonID.value]
        if let reason { data["reason"] = reason }
        return try await mutation("softDeleteSeason", data: data)
    }

    func batchSoftDeleteSeasons(
        brandID: BrandID,
        seasonIDs: [SeasonID],
        reason: String?
    ) async throws -> LookbookDeletionBatchResult {
        var data: [String: Any] = [
            "brandID": brandID.value,
            "seasonIDs": seasonIDs.map(\.value)
        ]
        if let reason { data["reason"] = reason }
        let response = try await transport.call("batchSoftDeleteSeasons", data: data)
        return try LookbookDeletionCloudFunctionsMapper.batchResult(response)
    }

    func restoreSeason(
        brandID: BrandID,
        seasonID: SeasonID
    ) async throws -> LookbookDeletionMutationReceipt {
        try await mutation(
            "restoreSeason",
            data: ["brandID": brandID.value, "seasonID": seasonID.value]
        )
    }

    func softDeletePost(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        reason: String?
    ) async throws -> LookbookDeletionMutationReceipt {
        var data: [String: Any] = [
            "brandID": brandID.value,
            "seasonID": seasonID.value,
            "postID": postID.value
        ]
        if let reason { data["reason"] = reason }
        return try await mutation("softDeletePost", data: data)
    }

    func batchSoftDeletePosts(
        brandID: BrandID,
        seasonID: SeasonID,
        postIDs: [PostID],
        reason: String?
    ) async throws -> LookbookDeletionBatchResult {
        var data: [String: Any] = [
            "brandID": brandID.value,
            "seasonID": seasonID.value,
            "postIDs": postIDs.map(\.value)
        ]
        if let reason { data["reason"] = reason }
        let response = try await transport.call("batchSoftDeletePosts", data: data)
        return try LookbookDeletionCloudFunctionsMapper.batchResult(response)
    }

    func restorePost(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID
    ) async throws -> LookbookDeletionMutationReceipt {
        try await mutation(
            "restorePost",
            data: [
                "brandID": brandID.value,
                "seasonID": seasonID.value,
                "postID": postID.value
            ]
        )
    }

    func listDeletionRequests(
        targetType: LookbookDeletionTargetType?,
        brandID: BrandID?,
        limit: Int,
        cursor: LookbookDeletionRequestPage.Cursor?
    ) async throws -> LookbookDeletionRequestPage {
        var data: [String: Any] = ["limit": limit]
        if let targetType { data["targetType"] = targetType.rawValue }
        if let brandID { data["brandID"] = brandID.value }
        if let cursor {
            data["cursorUpdatedAt"] = cursor.updatedAt
            data["cursorRequestID"] = cursor.requestID
        }
        let response = try await transport.call("listLookbookDeletionRequests", data: data)
        return try LookbookDeletionCloudFunctionsMapper.requestPage(response)
    }

    func retryFailedPurge(
        requestID: String
    ) async throws -> LookbookDeletionRetryReceipt {
        let response = try await transport.call(
            "retryFailedLookbookDeletionPurge",
            data: ["requestID": requestID]
        )
        return try LookbookDeletionCloudFunctionsMapper.retryReceipt(response)
    }

    private func mutation(
        _ name: String,
        data: [String: Any]
    ) async throws -> LookbookDeletionMutationReceipt {
        let response = try await transport.call(name, data: data)
        return try LookbookDeletionCloudFunctionsMapper.mutationReceipt(response)
    }
}
