//
//  CloudFunctionsSeasonImportJobRequestingRepository.swift
//  OutPick
//
//  Created by Codex on 4/23/26.
//

import Foundation

/// Cloud Functions를 통해 시즌 후보 기반 import job 생성을 요청합니다.
struct CloudFunctionsSeasonImportJobRequestingRepository: SeasonImportJobRequestingRepositoryProtocol {
    private let transport: any CloudFunctionsTransporting

    init(transport: any CloudFunctionsTransporting = FirebaseCloudFunctionsTransport()) {
        self.transport = transport
    }

    func requestSeasonCandidateImportJobs(
        brandID: BrandID,
        discoveryJobID: String,
        generation: Int,
        candidateIDs: [String],
        candidateSnapshotHash: String
    ) async throws -> SeasonImportBatchRequestResult {
        let response = try await transport.call(
            "requestSeasonCandidateImportJobs",
            data: [
                "brandID": brandID.value,
                "discoveryJobID": discoveryJobID,
                "generation": generation,
                "candidateIDs": candidateIDs,
                "candidateSnapshotHash": candidateSnapshotHash
            ]
        )
        return try SeasonImportCloudFunctionsMapper.batchRequestResult(response)
    }
}
