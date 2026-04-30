//
//  LoadCommentRepliesUseCase.swift
//  OutPick
//
//  Created by Codex on 5/1/26.
//

import Foundation

protocol LoadCommentRepliesUseCaseProtocol {
    func execute(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        parentCommentID: CommentID,
        page: PageRequest
    ) async throws -> PageResponse<Comment>
}

final class LoadCommentRepliesUseCase: LoadCommentRepliesUseCaseProtocol {
    private let commentRepository: any CommentRepositoryProtocol

    init(commentRepository: any CommentRepositoryProtocol) {
        self.commentRepository = commentRepository
    }

    func execute(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        parentCommentID: CommentID,
        page: PageRequest
    ) async throws -> PageResponse<Comment> {
        try await commentRepository.fetchReplies(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            parentCommentID: parentCommentID,
            page: page
        )
    }
}
