//
//  LoadPostDetailUseCase.swift
//  OutPick
//
//  Created by Codex on 4/24/26.
//

import Foundation

struct PostDetailContent: Equatable {
    let post: LookbookPost
    let comments: [Comment]
    let commentErrorMessage: String?
}

protocol LoadPostDetailUseCaseProtocol {
    func execute(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID
    ) async throws -> PostDetailContent
}

final class LoadPostDetailUseCase: LoadPostDetailUseCaseProtocol {
    private let postRepository: any PostRepositoryProtocol
    private let commentRepository: any CommentRepositoryProtocol

    init(
        postRepository: any PostRepositoryProtocol,
        commentRepository: any CommentRepositoryProtocol
    ) {
        self.postRepository = postRepository
        self.commentRepository = commentRepository
    }

    func execute(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID
    ) async throws -> PostDetailContent {
        let post = try await postRepository.fetchPost(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID
        )

        do {
            let representativeComment = try await commentRepository.fetchRepresentativeComment(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID
            )

            return PostDetailContent(
                post: post,
                comments: representativeComment.map { [$0] } ?? [],
                commentErrorMessage: nil
            )
        } catch {
            return PostDetailContent(
                post: post,
                comments: [],
                commentErrorMessage: "댓글을 불러오지 못했습니다."
            )
        }
    }
}
