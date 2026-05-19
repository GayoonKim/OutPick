//
//  SeasonCandidateRepositoryProtocol.swift
//  OutPick
//
//  Created by Codex on 4/23/26.
//

import Foundation

protocol SeasonCandidateRepositoryProtocol {
    func fetchSeasonCandidates(
        brandID: BrandID
    ) async throws -> [SeasonCandidate]
}
