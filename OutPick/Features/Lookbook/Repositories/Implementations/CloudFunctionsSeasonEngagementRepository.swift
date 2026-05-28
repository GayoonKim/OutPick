//
//  CloudFunctionsSeasonEngagementRepository.swift
//  OutPick
//
//  Created by Codex on 5/27/26.
//

import Foundation

final class CloudFunctionsSeasonEngagementRepository: SeasonEngagementRepositoryProtocol {
    private let cloudFunctionsManager: CloudFunctionsManager

    init(cloudFunctionsManager: CloudFunctionsManager = .shared) {
        self.cloudFunctionsManager = cloudFunctionsManager
    }

    func setLike(
        brandID: BrandID,
        seasonID: SeasonID,
        isLiked: Bool
    ) async throws -> SeasonEngagementResult {
        try await cloudFunctionsManager.setSeasonEngagement(
            brandID: brandID.value,
            seasonID: seasonID.value,
            isLiked: isLiked
        )
    }
}
