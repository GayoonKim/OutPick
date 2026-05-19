//
//  PostEngagementRepositoryProtocol.swift
//  OutPick
//
//  Created by Codex on 4/28/26.
//

import Foundation

protocol PostEngagementRepositoryProtocol {
    func setLike(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        isLiked: Bool
    ) async throws -> PostEngagementResult

    func setSave(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        isSaved: Bool
    ) async throws -> PostEngagementResult
}
