import Foundation

@MainActor
final class SeasonImportManagementViewModel: ObservableObject {
    @Published private(set) var jobs: [SeasonImportJob] = []
    @Published private(set) var isLoading = false
    @Published private(set) var retryingJobID: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var discoveryResult: SeasonCandidateDiscoveryResult?
    @Published private(set) var isMutatingDiscovery = false
    @Published private(set) var discoveryErrorMessage: String?

    var presentedErrorMessage: String? {
        discoveryErrorMessage ?? errorMessage
    }

    private let brandID: BrandID
    private let useCase: any ManageSeasonImportJobsUseCaseProtocol
    private let discoveryRepository: any SeasonCandidateDiscoveryRepositoryProtocol

    init(
        brandID: BrandID,
        useCase: any ManageSeasonImportJobsUseCaseProtocol,
        discoveryRepository: any SeasonCandidateDiscoveryRepositoryProtocol
    ) {
        self.brandID = brandID
        self.useCase = useCase
        self.discoveryRepository = discoveryRepository
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            jobs = try await useCase.loadJobs(brandID: brandID)
        } catch {
            errorMessage = "시즌 가져오기 현황을 불러오지 못했습니다."
        }
    }

    func monitor() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                guard let self else { return }
                await self.load()
                await self.pollActiveJobs()
            }
            group.addTask { [weak self] in
                await self?.observeLatestDiscovery()
            }
        }
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
        discoveryErrorMessage = nil
    }

    func requestDiscovery() async {
        await mutateDiscovery(errorText: "시즌 탐색을 시작하지 못했습니다.") {
            self.discoveryResult = try await self.discoveryRepository
                .requestSeasonDiscovery(brandID: self.brandID)
        }
    }

    func retryDiscovery() async {
        guard let discoveryResult else { return }
        await mutateDiscovery(errorText: "시즌 탐색을 다시 시작하지 못했습니다.") {
            try await self.discoveryRepository.retrySeasonDiscovery(
                brandID: self.brandID,
                jobID: discoveryResult.jobID
            )
        }
    }

    func cancelDiscovery() async {
        guard let discoveryResult else { return }
        await mutateDiscovery(errorText: "시즌 탐색을 취소하지 못했습니다.") {
            try await self.discoveryRepository.cancelSeasonDiscovery(
                brandID: self.brandID,
                jobID: discoveryResult.jobID
            )
        }
    }

    func requestDiscoveryImprovement() async {
        guard let discoveryResult else { return }
        await mutateDiscovery(errorText: "추출 개선을 요청하지 못했습니다.") {
            try await self.discoveryRepository.requestSeasonDiscoveryImprovement(
                brandID: self.brandID,
                job: discoveryResult
            )
            self.discoveryResult = discoveryResult.markingImprovementRequested()
        }
    }

    func reanalyzeDiscovery() async {
        guard let discoveryResult else { return }
        await mutateDiscovery(errorText: "시즌 목록을 다시 가져오지 못했습니다.") {
            self.discoveryResult = try await self.discoveryRepository
                .reanalyzeSeasonDiscoveryWithLatestExtractor(
                    brandID: self.brandID,
                    job: discoveryResult
                )
        }
    }

    private func observeLatestDiscovery() async {
        do {
            for try await result in discoveryRepository
                .observeLatestSeasonDiscovery(brandID: brandID) {
                guard !Task.isCancelled else { return }
                discoveryResult = result
            }
        } catch is CancellationError {
            return
        } catch {
            discoveryErrorMessage = "시즌 탐색 상태를 불러오지 못했습니다."
        }
    }

    private func mutateDiscovery(
        errorText: String,
        operation: @escaping @MainActor () async throws -> Void
    ) async {
        guard !isMutatingDiscovery else { return }
        isMutatingDiscovery = true
        discoveryErrorMessage = nil
        defer { isMutatingDiscovery = false }
        do {
            try await operation()
        } catch {
            discoveryErrorMessage = errorText
        }
    }
}
