//
//  SeasonImportJobRequestingRepositoryProtocol.swift
//  OutPick
//
//  Created by Codex on 4/23/26.
//

import Foundation

protocol SeasonImportJobRequestingRepositoryProtocol {
    func requestSeasonCandidateImportJobs(
        brandID: BrandID,
        candidateIDs: [String]
    ) async throws -> SeasonImportBatchRequestResult
}
