//
//  CloudFunctionsBrandEngagementRepository.swift
//  OutPick
//
//  Created by Codex on 5/25/26.
//

import Foundation

final class CloudFunctionsBrandEngagementRepository: BrandEngagementRepositoryProtocol {
    private let transport: any CloudFunctionsTransporting

    init(transport: any CloudFunctionsTransporting = FirebaseCloudFunctionsTransport()) {
        self.transport = transport
    }

    func setLike(
        brandID: BrandID,
        isLiked: Bool
    ) async throws -> BrandEngagementResult {
        let response = try await transport.call(
            "setBrandEngagement",
            data: ["brandID": brandID.value, "isLiked": isLiked]
        )
        return try EngagementCloudFunctionsMapper.brand(response)
    }
}
