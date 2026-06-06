import Foundation

protocol ManageSeasonImportJobsUseCaseProtocol {
    func loadJobs(brandID: BrandID) async throws -> [SeasonImportJob]
    func retryAssets(
        brandID: BrandID,
        sourceJobID: String
    ) async throws -> SeasonAssetRetryReceipt
}

final class ManageSeasonImportJobsUseCase: ManageSeasonImportJobsUseCaseProtocol {
    private let jobRepository: any SeasonImportJobRepositoryProtocol
    private let retryRepository: any SeasonAssetRetryRequestingRepository

    init(
        jobRepository: any SeasonImportJobRepositoryProtocol,
        retryRepository: any SeasonAssetRetryRequestingRepository
    ) {
        self.jobRepository = jobRepository
        self.retryRepository = retryRepository
    }

    func loadJobs(brandID: BrandID) async throws -> [SeasonImportJob] {
        try await jobRepository.fetchLatestJobs(
            brandID: brandID,
            limit: 30
        )
    }

    func retryAssets(
        brandID: BrandID,
        sourceJobID: String
    ) async throws -> SeasonAssetRetryReceipt {
        try await retryRepository.requestAssetRetry(
            brandID: brandID,
            sourceJobID: sourceJobID
        )
    }
}
