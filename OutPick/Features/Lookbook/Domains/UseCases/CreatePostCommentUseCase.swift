//
//  CreatePostCommentUseCase.swift
//  OutPick
//
//  Created by Codex on 5/4/26.
//

import Foundation

enum CommentSubmissionError: LocalizedError {
    case emptyMessage
    case messageTooLong

    var errorDescription: String? {
        switch self {
        case .emptyMessage:
            return "댓글 내용을 입력해주세요."
        case .messageTooLong:
            return "댓글은 1,000자까지 입력할 수 있어요."
        }
    }
}

enum CommentInputPolicy {
    static let maximumUTF16Length = 1_000
}

protocol CreatePostCommentUseCaseProtocol {
    func execute(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        message: String,
        clientRequestID: UUID
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
        message: String,
        clientRequestID: UUID
    ) async throws -> CommentMutationResult {
        let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedMessage.isEmpty == false else {
            throw CommentSubmissionError.emptyMessage
        }
        guard normalizedMessage.utf16.count <= CommentInputPolicy.maximumUTF16Length else {
            throw CommentSubmissionError.messageTooLong
        }

        try debugFailureInjectionStore?.throwIfNeeded(.createComment)
        return try await repository.createComment(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            message: normalizedMessage,
            clientRequestID: clientRequestID
        )
    }
}
