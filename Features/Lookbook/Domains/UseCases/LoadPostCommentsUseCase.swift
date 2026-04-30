//
//  LoadPostCommentsUseCase.swift
//  OutPick
//
//  Created by Codex on 5/1/26.
//

import Foundation

struct PostCommentsContent: Equatable {
    let pinnedComments: [Comment]
    let representativeComment: Comment?
    let rootComments: PageResponse<Comment>
}

protocol LoadPostCommentsUseCaseProtocol {
    func execute(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        sort: CommentSortOption,
        page: PageRequest
    ) async throws -> PostCommentsContent

    func loadRootComments(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        sort: CommentSortOption,
        page: PageRequest
    ) async throws -> PageResponse<Comment>
}

final class LoadPostCommentsUseCase: LoadPostCommentsUseCaseProtocol {
    private let commentRepository: any CommentRepositoryProtocol
    private let pinnedCommentLimit: Int

    init(
        commentRepository: any CommentRepositoryProtocol,
        pinnedCommentLimit: Int = 3
    ) {
        self.commentRepository = commentRepository
        self.pinnedCommentLimit = pinnedCommentLimit
    }

    func execute(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        sort: CommentSortOption,
        page: PageRequest
    ) async throws -> PostCommentsContent {
        async let pinnedComments = commentRepository.fetchPinnedRootComments(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            limit: pinnedCommentLimit
        )
        async let representativeComment = commentRepository.fetchRepresentativeComment(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID
        )
        async let rootComments = commentRepository.fetchRootComments(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            sort: sort,
            page: page
        )

        let resolvedPinnedComments = try await pinnedComments
        let resolvedRepresentativeComment = try await representativeComment
        let resolvedRootComments = try await rootComments

        let excludedIDs = duplicateExcludedIDs(
            pinnedComments: resolvedPinnedComments,
            representativeComment: resolvedRepresentativeComment
        )
        let visibleRootComments = resolvedRootComments.items.filter {
            excludedIDs.contains($0.id) == false
        }

        return PostCommentsContent(
            pinnedComments: resolvedPinnedComments,
            representativeComment: resolvedRepresentativeComment,
            rootComments: PageResponse(
                items: visibleRootComments,
                nextCursor: resolvedRootComments.nextCursor
            )
        )
    }

    func loadRootComments(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        sort: CommentSortOption,
        page: PageRequest
    ) async throws -> PageResponse<Comment> {
        try await commentRepository.fetchRootComments(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            sort: sort,
            page: page
        )
    }

    private func duplicateExcludedIDs(
        pinnedComments: [Comment],
        representativeComment: Comment?
    ) -> Set<CommentID> {
        var ids = Set(pinnedComments.map(\.id))
        if let representativeComment {
            ids.insert(representativeComment.id)
        }
        return ids
    }
}
