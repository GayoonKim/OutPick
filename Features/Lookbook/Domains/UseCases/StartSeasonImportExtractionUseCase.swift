//
//  StartSeasonImportExtractionUseCase.swift
//  OutPick
//
//  Created by Codex on 4/24/26.
//

import Foundation

protocol StartSeasonImportExtractionUseCaseProtocol {
    func execute(
        brandID: BrandID,
        candidates: [SeasonCandidate]
    ) async throws -> SeasonImportBatchProcessResult

    func loadProgress(
        brandID: BrandID,
        candidateIDs: [String]
    ) async throws -> SeasonImportExtractionProgress
}

final class StartSeasonImportExtractionUseCase: StartSeasonImportExtractionUseCaseProtocol {
    private let processingRepository: any SeasonImportJobProcessingRepositoryProtocol
    private let seasonImportJobRepository: any SeasonImportJobRepositoryProtocol

    init(
        processingRepository: any SeasonImportJobProcessingRepositoryProtocol,
        seasonImportJobRepository: any SeasonImportJobRepositoryProtocol
    ) {
        self.processingRepository = processingRepository
        self.seasonImportJobRepository = seasonImportJobRepository
    }

    func execute(
        brandID: BrandID,
        candidates: [SeasonCandidate]
    ) async throws -> SeasonImportBatchProcessResult {
        let candidateIDs = candidates.map(\.id)
        return try await processingRepository
            .requestSeasonCandidateImportsAndProcess(
                brandID: brandID,
                candidateIDs: candidateIDs
            )
    }

    func loadProgress(
        brandID: BrandID,
        candidateIDs: [String]
    ) async throws -> SeasonImportExtractionProgress {
        let jobs = try await seasonImportJobRepository.fetchJobs(
            brandID: brandID,
            sourceCandidateIDs: candidateIDs
        )
        let latestJobsByCandidateID = latestJobs(from: jobs)

        return SeasonImportExtractionProgress(
            totalCount: candidateIDs.count,
            matchedJobCount: latestJobsByCandidateID.count,
            completedCount: latestJobsByCandidateID.values
                .filter { $0.status.isSeasonReadyFlowFinished }
                .count,
            failedCount: latestJobsByCandidateID.values
                .filter { $0.status == .failed }
                .count
        )
    }

    private func latestJobs(
        from jobs: [SeasonImportJob]
    ) -> [String: SeasonImportJob] {
        jobs.reduce(into: [String: SeasonImportJob]()) { partialResult, job in
            guard let sourceCandidateID = job.sourceCandidateID else { return }

            guard let existingJob = partialResult[sourceCandidateID] else {
                partialResult[sourceCandidateID] = job
                return
            }

            if existingJob.updatedAt <= job.updatedAt {
                partialResult[sourceCandidateID] = job
            }
        }
    }
}
