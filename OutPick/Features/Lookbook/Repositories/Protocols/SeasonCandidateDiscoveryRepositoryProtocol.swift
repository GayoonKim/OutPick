//
//  SeasonCandidateDiscoveryRepositoryProtocol.swift
//  OutPick
//
//  Created by Codex on 4/23/26.
//

import Foundation

protocol SeasonCandidateDiscoveryRepositoryProtocol {
    func discoverSeasonCandidates(
        brandID: BrandID
    ) async throws -> SeasonCandidateDiscoveryResult
}
