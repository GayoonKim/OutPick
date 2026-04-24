//
//  CloudFunctionsSeasonCandidateDiscoveryRepository.swift
//  OutPick
//
//  Created by Codex on 4/23/26.
//

import Foundation

struct CloudFunctionsSeasonCandidateDiscoveryRepository: SeasonCandidateDiscoveryRepositoryProtocol {
    func discoverSeasonCandidates(
        brandID: BrandID
    ) async throws -> SeasonCandidateDiscoveryResult {
        try await CloudFunctionsManager.shared.discoverSeasonCandidates(
            brandID: brandID.value
        )
    }
}
