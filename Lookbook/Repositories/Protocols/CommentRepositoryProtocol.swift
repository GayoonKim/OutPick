//
//  CommentRepositoryProtocol.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation

protocol CommentRepositoryProtocol {
    func fetchComments(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        page: PageRequest
    ) async throws -> PageResponse<Comment>
}
