//
//  CreatePostCommentUseCase.swift
//  OutPick
//
//  Created by Codex on 5/4/26.
//

import Foundation

enum CommentSubmissionError: LocalizedError {
    case emptyMessage

    var errorDescription: String? {
        switch self {
        case .emptyMessage:
            return "댓글 내용을 입력해주세요."
        }
    }
}

protocol CreatePostCommentUseCaseProtocol {
    func execute(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        message: String
    ) async throws -> CommentMutationResult
}

final class CreatePostCommentUseCase: CreatePostCommentUseCaseProtocol {
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
        message: String
    ) async throws -> CommentMutationResult {
        let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedMessage.isEmpty == false else {
            throw CommentSubmissionError.emptyMessage
        }

        try debugFailureInjectionStore?.throwIfNeeded(.createComment)
        return try await repository.createComment(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            message: normalizedMessage
        )
    }
}
