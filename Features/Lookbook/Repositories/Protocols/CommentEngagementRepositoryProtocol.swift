//
//  CommentEngagementRepositoryProtocol.swift
//  OutPick
//
//  Created by Codex on 5/14/26.
//

import Foundation

protocol CommentEngagementRepositoryProtocol {
    func setLike(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        commentID: CommentID,
        isLiked: Bool
    ) async throws -> CommentEngagementResult
}
