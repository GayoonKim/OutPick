//
//  CloudFunctionsSeasonCandidateDiscoveryRepository.swift
//  OutPick
//
//  Created by Codex on 4/23/26.
//

import Foundation

enum SeasonCandidateDiscoveryError: LocalizedError {
    case failed(loadedCount: Int)

    var errorDescription: String? {
        switch self {
        case .failed(let loadedCount):
            return "시즌 \(loadedCount)개를 불러왔습니다."
        }
    }
}

struct CloudFunctionsSeasonCandidateDiscoveryRepository: SeasonCandidateDiscoveryRepositoryProtocol {
    func discoverSeasonCandidates(
        brandID: BrandID
    ) async throws -> SeasonCandidateDiscoveryResult {
        let diagnostic = try await CloudFunctionsManager.shared.runLookbookExtractionDiagnostic(
            brandID: brandID.value,
            type: .seasonDiscovery
        )
        let candidateCount = diagnostic.seasonDiscovery?.storedCandidateCount ?? 0
        if diagnostic.status == .failed {
            throw SeasonCandidateDiscoveryError.failed(loadedCount: candidateCount)
        }
        return SeasonCandidateDiscoveryResult(
            brandID: diagnostic.brandID,
            sourceURL: diagnostic.sourceURL ?? "",
            candidateCount: candidateCount
        )
    }
}
