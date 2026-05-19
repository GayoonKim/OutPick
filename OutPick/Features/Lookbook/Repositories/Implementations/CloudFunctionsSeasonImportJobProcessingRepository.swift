//
//  CloudFunctionsSeasonImportJobProcessingRepository.swift
//  OutPick
//
//  Created by Codex on 4/23/26.
//

import Foundation

/// Cloud Functions를 통해 대기 중인 시즌 import job 처리를 요청합니다.
struct CloudFunctionsSeasonImportJobProcessingRepository: SeasonImportJobProcessingRepositoryProtocol {
    func processNextSeasonImportJob(
        brandID: BrandID
    ) async throws -> SeasonImportProcessResult {
        try await CloudFunctionsManager.shared.processNextSeasonImportJob(
            brandID: brandID.value
        )
    }

    func processSeasonImportJobs(
        brandID: BrandID,
        jobIDs: [String]
    ) async throws -> SeasonImportBatchProcessResult {
        try await CloudFunctionsManager.shared.processSeasonImportJobs(
            brandID: brandID.value,
            jobIDs: jobIDs
        )
    }

    func requestSeasonCandidateImportsAndProcess(
        brandID: BrandID,
        candidateIDs: [String]
    ) async throws -> SeasonImportBatchProcessResult {
        try await CloudFunctionsManager.shared.requestSeasonCandidateImportsAndProcess(
            brandID: brandID.value,
            candidateIDs: candidateIDs
        )
    }
}
