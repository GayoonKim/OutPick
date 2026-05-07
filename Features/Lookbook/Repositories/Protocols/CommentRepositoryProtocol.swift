//
//  CommentRepositoryProtocol.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation

protocol CommentRepositoryProtocol {
    func fetchRepresentativeComment(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID
    ) async throws -> Comment?

    func fetchPinnedRootComments(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        limit: Int
    ) async throws -> [Comment]

    func fetchRootComments(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        sort: CommentSortOption,
        page: PageRequest
    ) async throws -> PageResponse<Comment>

    func fetchReplies(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        parentCommentID: CommentID,
        page: PageRequest
    ) async throws -> PageResponse<Comment>

    func fetchVisibleCommentCount(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        hiddenUserIDs: Set<UserID>
    ) async throws -> Int
}
