//
//  BrandEngagementRepositoryProtocol.swift
//  OutPick
//
//  Created by Codex on 5/25/26.
//

import Foundation

protocol BrandEngagementRepositoryProtocol {
    func setLike(
        brandID: BrandID,
        isLiked: Bool
    ) async throws -> BrandEngagementResult
}
