//
//  PostRepositoryProtocol.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation

protocol PostRepositoryProtocol {
    func fetchPosts(
        brandID: BrandID,
        seasonID: SeasonID,
        sort: PostSortOption,
        filterTagIDs: [TagID],
        page: PageRequest
    ) async throws -> PageResponse<LookbookPost>

    func fetchPost(brandID: BrandID, seasonID: SeasonID, postID: PostID) async throws -> LookbookPost

    func fetchPostsByTag(tagID: TagID, sort: PostSortOption, page: PageRequest) async throws -> PageResponse<LookbookPost>
}
