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
    ) async throws -> SeasonImportBatchRequestResult

    func loadProgress(
        brandID: BrandID,
        candidateIDs: [String]
    ) async throws -> SeasonImportExtractionProgress
}

final class StartSeasonImportExtractionUseCase: StartSeasonImportExtractionUseCaseProtocol {
    private let importJobRequestingRepository: any SeasonImportJobRequestingRepositoryProtocol
    private let seasonImportJobRepository: any SeasonImportJobRepositoryProtocol

    init(
        importJobRequestingRepository: any SeasonImportJobRequestingRepositoryProtocol,
        seasonImportJobRepository: any SeasonImportJobRepositoryProtocol
    ) {
        self.importJobRequestingRepository = importJobRequestingRepository
        self.seasonImportJobRepository = seasonImportJobRepository
    }

    func execute(
        brandID: BrandID,
        candidates: [SeasonCandidate]
    ) async throws -> SeasonImportBatchRequestResult {
        let candidateIDs = candidates.map(\.id)
        return try await importJobRequestingRepository
            .requestSeasonCandidateImportJobs(
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
        let items = progressItems(
            candidateIDs: candidateIDs,
            latestJobsByCandidateID: latestJobsByCandidateID
        )

        return SeasonImportExtractionProgress(
            totalCount: candidateIDs.count,
            matchedJobCount: latestJobsByCandidateID.count,
            completedCount: items.filter { $0.status != .processing }.count,
            failedCount: items.filter { $0.status == .failed }.count,
            items: items
        )
    }

    private func progressItems(
        candidateIDs: [String],
        latestJobsByCandidateID: [String: SeasonImportJob]
    ) -> [SeasonImportExtractionProgress.Item] {
        candidateIDs.map { candidateID in
            guard let job = latestJobsByCandidateID[candidateID] else {
                return SeasonImportExtractionProgress.Item(
                    candidateID: candidateID,
                    jobID: nil,
                    status: .processing
                )
            }

            return SeasonImportExtractionProgress.Item(
                candidateID: candidateID,
                jobID: job.id,
                status: progressStatus(for: job)
            )
        }
    }

    private func progressStatus(
        for job: SeasonImportJob
    ) -> SeasonImportExtractionProgress.ItemStatus {
        switch job.status {
        case .succeeded:
            return .succeeded
        case .partialFailed, .failed, .cancelled:
            return .failed
        case .queued, .processing, .awaitingReview:
            return .processing
        }
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
