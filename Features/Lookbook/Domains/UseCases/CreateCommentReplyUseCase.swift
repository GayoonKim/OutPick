//
//  CreateCommentReplyUseCase.swift
//  OutPick
//
//  Created by Codex on 5/4/26.
//

import Foundation

protocol CreateCommentReplyUseCaseProtocol {
    func execute(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        parentCommentID: CommentID,
        message: String
    ) async throws -> CommentMutationResult
}

final class CreateCommentReplyUseCase: CreateCommentReplyUseCaseProtocol {
    private let repository: any CommentWritingRepositoryProtocol

    init(repository: any CommentWritingRepositoryProtocol) {
        self.repository = repository
    }

    func execute(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        parentCommentID: CommentID,
        message: String
    ) async throws -> CommentMutationResult {
        let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedMessage.isEmpty == false else {
            throw CommentSubmissionError.emptyMessage
        }

        return try await repository.createReply(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            parentCommentID: parentCommentID,
            message: normalizedMessage
        )
    }
}
