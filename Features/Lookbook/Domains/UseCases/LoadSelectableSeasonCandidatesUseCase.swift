//
//  LoadSelectableSeasonCandidatesUseCase.swift
//  OutPick
//
//  Created by Codex on 4/24/26.
//

import Foundation

protocol LoadSelectableSeasonCandidatesUseCaseProtocol {
    func execute(
        brandID: BrandID
    ) async throws -> [SeasonCandidate]
}

final class LoadSelectableSeasonCandidatesUseCase: LoadSelectableSeasonCandidatesUseCaseProtocol {
    private let candidateRepository: any SeasonCandidateRepositoryProtocol
    private let seasonImportJobRepository: any SeasonImportJobRepositoryProtocol

    init(
        candidateRepository: any SeasonCandidateRepositoryProtocol,
        seasonImportJobRepository: any SeasonImportJobRepositoryProtocol
    ) {
        self.candidateRepository = candidateRepository
        self.seasonImportJobRepository = seasonImportJobRepository
    }

    func execute(
        brandID: BrandID
    ) async throws -> [SeasonCandidate] {
        async let fetchedCandidates = candidateRepository.fetchSeasonCandidates(
            brandID: brandID
        )
        async let activeJobs = seasonImportJobRepository.fetchActiveJobs(
            brandID: brandID
        )

        let candidates = try await fetchedCandidates
        let jobs = try await activeJobs

        let activeCandidateIDs = Set(jobs.compactMap(\.sourceCandidateID))
        let activeSeasonURLs = Set(jobs.map(\.sourceURL))

        return candidates.filter { candidate in
            !activeCandidateIDs.contains(candidate.id) &&
            !activeSeasonURLs.contains(candidate.seasonURL)
        }
    }
}
