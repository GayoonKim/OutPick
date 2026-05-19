//
//  DeleteCommentUseCase.swift
//  OutPick
//
//  Created by Codex on 5/7/26.
//

import Foundation

protocol DeleteCommentUseCaseProtocol {
    func execute(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        commentID: CommentID,
        reason: String?
    ) async throws -> CommentDeletionResult
}

final class DeleteCommentUseCase: DeleteCommentUseCaseProtocol {
    private let repository: any CommentWritingRepositoryProtocol
    private let debugFailureInjectionStore: LookbookDebugFailureInjectionStore?

    init(
        repository: any CommentWritingRepositoryProtocol,
        debugFailureInjectionStore: LookbookDebugFailureInjectionStore? = nil
    ) {
        self.repository = repository
        self.debugFailureInjectionStore = debugFailureInjectionStore
    }

    func execute(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        commentID: CommentID,
        reason: String?
    ) async throws -> CommentDeletionResult {
        let normalizedReason = reason?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        try debugFailureInjectionStore?.throwIfNeeded(.deleteComment)
        return try await repository.deleteComment(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            commentID: commentID,
            reason: normalizedReason?.isEmpty == true ? nil : normalizedReason
        )
    }
}
