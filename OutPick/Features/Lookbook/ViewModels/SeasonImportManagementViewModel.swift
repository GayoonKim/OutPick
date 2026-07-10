import Foundation

@MainActor
final class SeasonImportManagementViewModel: ObservableObject {
    @Published private(set) var jobs: [SeasonImportJob] = []
    @Published private(set) var isLoading = false
    @Published private(set) var retryingJobID: String?
    @Published private(set) var errorMessage: String?

    private let brandID: BrandID
    private let useCase: any ManageSeasonImportJobsUseCaseProtocol

    init(
        brandID: BrandID,
        useCase: any ManageSeasonImportJobsUseCaseProtocol
    ) {
        self.brandID = brandID
        self.useCase = useCase
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            jobs = try await useCase.loadJobs(brandID: brandID)
        } catch {
            errorMessage = jobs.isEmpty ? nil : "시즌 가져오기 현황을 불러오지 못했습니다."
        }
    }

    func monitor() async {
        await load()
        await pollActiveJobs()
    }

    func hasActiveRetry(for job: SeasonImportJob) -> Bool {
        job.isAssetRetryInFlight
    }

    private func pollActiveJobs() async {
        while !Task.isCancelled && jobs.contains(where: {
            $0.status == .queued || $0.status == .processing || $0.isAssetRetryInFlight
        }) {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            await load()
        }
    }

    func retryAssets(for job: SeasonImportJob) async {
        guard job.canRetryAssets, retryingJobID == nil else { return }
        retryingJobID = job.id
        errorMessage = nil
        defer { retryingJobID = nil }

        do {
            _ = try await useCase.retryAssets(
                brandID: brandID,
                sourceJobID: job.id
            )
            jobs = try await useCase.loadJobs(brandID: brandID)
            await pollActiveJobs()
        } catch {
            errorMessage = "재시도하지 못했습니다."
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
