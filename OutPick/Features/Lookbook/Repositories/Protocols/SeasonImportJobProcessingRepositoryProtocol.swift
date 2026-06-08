//
//  SeasonImportJobProcessingRepositoryProtocol.swift
//  OutPick
//
//  Created by Codex on 4/23/26.
//

import Foundation

protocol SeasonImportJobProcessingRepositoryProtocol {
    func requestSeasonCandidateImportsAndProcess(
        brandID: BrandID,
        candidateIDs: [String]
    ) async throws -> SeasonImportBatchProcessResult
}
