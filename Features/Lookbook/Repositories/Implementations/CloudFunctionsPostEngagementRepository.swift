//
//  CloudFunctionsPostEngagementRepository.swift
//  OutPick
//
//  Created by Codex on 4/28/26.
//

import Foundation

final class CloudFunctionsPostEngagementRepository: PostEngagementRepositoryProtocol {
    private let cloudFunctionsManager: CloudFunctionsManager

    init(cloudFunctionsManager: CloudFunctionsManager = .shared) {
        self.cloudFunctionsManager = cloudFunctionsManager
    }

    func setLike(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        isLiked: Bool
    ) async throws -> PostEngagementResult {
        try await cloudFunctionsManager.setPostEngagement(
            brandID: brandID.value,
            seasonID: seasonID.value,
            postID: postID.value,
            kind: "like",
            isEnabled: isLiked
        )
    }

    func setSave(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        isSaved: Bool
    ) async throws -> PostEngagementResult {
        try await cloudFunctionsManager.setPostEngagement(
            brandID: brandID.value,
            seasonID: seasonID.value,
            postID: postID.value,
            kind: "save",
            isEnabled: isSaved
        )
    }
}
