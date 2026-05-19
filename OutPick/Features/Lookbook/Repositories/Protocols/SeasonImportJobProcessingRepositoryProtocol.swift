//
//  SeasonImportJobProcessingRepositoryProtocol.swift
//  OutPick
//
//  Created by Codex on 4/23/26.
//

import Foundation

protocol SeasonImportJobProcessingRepositoryProtocol {
    func processNextSeasonImportJob(
        brandID: BrandID
    ) async throws -> SeasonImportProcessResult

    func processSeasonImportJobs(
        brandID: BrandID,
        jobIDs: [String]
    ) async throws -> SeasonImportBatchProcessResult

    func requestSeasonCandidateImportsAndProcess(
        brandID: BrandID,
        candidateIDs: [String]
    ) async throws -> SeasonImportBatchProcessResult
}
