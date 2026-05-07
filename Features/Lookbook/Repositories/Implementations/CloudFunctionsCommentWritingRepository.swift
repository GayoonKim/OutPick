//
//  CloudFunctionsCommentWritingRepository.swift
//  OutPick
//
//  Created by Codex on 5/4/26.
//

import Foundation

final class CloudFunctionsCommentWritingRepository: CommentWritingRepositoryProtocol {
    private let cloudFunctionsManager: CloudFunctionsManager

    init(cloudFunctionsManager: CloudFunctionsManager = .shared) {
        self.cloudFunctionsManager = cloudFunctionsManager
    }

    func createComment(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        message: String
    ) async throws -> CommentMutationResult {
        try await cloudFunctionsManager.createComment(
            brandID: brandID.value,
            seasonID: seasonID.value,
            postID: postID.value,
            message: message
        )
    }

    func createReply(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        parentCommentID: CommentID,
        message: String
    ) async throws -> CommentMutationResult {
        try await cloudFunctionsManager.createReply(
            brandID: brandID.value,
            seasonID: seasonID.value,
            postID: postID.value,
            parentCommentID: parentCommentID.value,
            message: message
        )
    }

    func deleteComment(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        commentID: CommentID,
        reason: String?
    ) async throws -> CommentDeletionResult {
        try await cloudFunctionsManager.deleteComment(
            brandID: brandID.value,
            seasonID: seasonID.value,
            postID: postID.value,
            commentID: commentID.value,
            reason: reason
        )
    }
}
