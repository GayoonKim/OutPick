//
//  CloudFunctionsBrandEngagementRepository.swift
//  OutPick
//
//  Created by Codex on 5/25/26.
//

import Foundation

final class CloudFunctionsBrandEngagementRepository: BrandEngagementRepositoryProtocol {
    private let cloudFunctionsManager: CloudFunctionsManager

    init(cloudFunctionsManager: CloudFunctionsManager = .shared) {
        self.cloudFunctionsManager = cloudFunctionsManager
    }

    func setLike(
        brandID: BrandID,
        isLiked: Bool
    ) async throws -> BrandEngagementResult {
        try await cloudFunctionsManager.setBrandEngagement(
            brandID: brandID.value,
            isLiked: isLiked
        )
    }
}
