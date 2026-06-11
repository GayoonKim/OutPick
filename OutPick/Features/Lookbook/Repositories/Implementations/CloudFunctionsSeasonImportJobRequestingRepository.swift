//
//  CloudFunctionsSeasonImportJobRequestingRepository.swift
//  OutPick
//
//  Created by Codex on 4/23/26.
//

import Foundation

/// Cloud Functions를 통해 시즌 후보 기반 import job 생성을 요청합니다.
struct CloudFunctionsSeasonImportJobRequestingRepository: SeasonImportJobRequestingRepositoryProtocol {
    func requestSeasonCandidateImportJobs(
        brandID: BrandID,
        candidateIDs: [String]
    ) async throws -> SeasonImportBatchRequestResult {
        try await CloudFunctionsManager.shared.requestSeasonCandidateImportJobs(
            brandID: brandID.value,
            candidateIDs: candidateIDs
        )
    }
}
