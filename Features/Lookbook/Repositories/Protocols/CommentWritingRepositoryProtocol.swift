//
//  CommentWritingRepositoryProtocol.swift
//  OutPick
//
//  Created by Codex on 5/4/26.
//

import Foundation

protocol CommentWritingRepositoryProtocol {
    func createComment(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        message: String
    ) async throws -> CommentMutationResult

    func createReply(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        parentCommentID: CommentID,
        message: String
    ) async throws -> CommentMutationResult

    func deleteComment(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        commentID: CommentID,
        reason: String?
    ) async throws -> CommentDeletionResult
}
