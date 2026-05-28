//
//  SeasonEngagementRepositoryProtocol.swift
//  OutPick
//
//  Created by Codex on 5/27/26.
//

import Foundation

protocol SeasonEngagementRepositoryProtocol {
    func setLike(
        brandID: BrandID,
        seasonID: SeasonID,
        isLiked: Bool
    ) async throws -> SeasonEngagementResult
}
