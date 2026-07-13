//
//  CloudFunctionsSeasonEngagementRepository.swift
//  OutPick
//
//  Created by Codex on 5/27/26.
//

import Foundation

final class CloudFunctionsSeasonEngagementRepository: SeasonEngagementRepositoryProtocol {
    private let transport: any CloudFunctionsTransporting

    init(transport: any CloudFunctionsTransporting = FirebaseCloudFunctionsTransport()) {
        self.transport = transport
    }

    func setLike(
        brandID: BrandID,
        seasonID: SeasonID,
        isLiked: Bool
    ) async throws -> SeasonEngagementResult {
        let response = try await transport.call(
            "setSeasonEngagement",
            data: [
                "brandID": brandID.value,
                "seasonID": seasonID.value,
                "isLiked": isLiked
            ]
        )
        return try EngagementCloudFunctionsMapper.season(response)
    }
}
