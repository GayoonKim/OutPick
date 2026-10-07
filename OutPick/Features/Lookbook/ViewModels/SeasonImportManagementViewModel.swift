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
    @Published private(set) var queueReceipts: [LookbookImportQueueReceipt] = []

    var presentedErrorMessage: String? {
        discoveryErrorMessage ?? errorMessage
    }

    private let brandID: BrandID
    private let useCase: any ManageSeasonImportJobsUseCaseProtocol
    private let discoveryRepository: any SeasonCandidateDiscoveryRepositoryProtocol
    private let queueUseCase: (any StartSeasonImportExtractionUseCaseProtocol)?
    private var isScreenActive = true
    private var isMonitoring = false
    private var pollingTask: Task<Void, Never>?

    init(
        brandID: BrandID,
        useCase: any ManageSeasonImportJobsUseCaseProtocol,
        discoveryRepository: any SeasonCandidateDiscoveryRepositoryProtocol,
        queueUseCase: (any StartSeasonImportExtractionUseCaseProtocol)? = nil
    ) {
        self.brandID = brandID
        self.useCase = useCase
        self.discoveryRepository = discoveryRepository
        self.queueUseCase = queueUseCase
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            jobs = try await useCase.loadJobs(brandID: brandID)
            if let queueUseCase {
                queueReceipts = try await queueUseCase.reconcileUnsettledRequests(brandID: brandID)
            }
        } catch {
            errorMessage = "시즌 가져오기 현황을 불러오지 못했습니다."
        }
    }

    func monitor() async {
        guard !isMonitoring else { return }
        isMonitoring = true
        defer {
            isMonitoring = false
            pollingTask?.cancel()
            pollingTask = nil
        }
        await load()
        startPollingIfNeeded()
        await observeLatestDiscovery()
    }

    func hasActiveRetry(for job: SeasonImportJob) -> Bool {
        job.isAssetRetryInFlight
    }

    func setScreenActive(_ active: Bool) {
        isScreenActive = active
        if active {
            startPollingIfNeeded()
        } else {
            pollingTask?.cancel()
        }
    }

    private func pollActiveJobs() async {
        defer {
            pollingTask = nil
            startPollingIfNeeded()
        }
        var consecutiveErrors = 0
        while !Task.isCancelled && isScreenActive && hasActiveWork {
            let waiting = queueReceipts.contains {
                $0.state == .preparing || $0.state == .queued || $0.state == .retryWaiting
            }
            let seconds: UInt64 = consecutiveErrors > 0 ? [10, 20, 40, 60][min(consecutiveErrors - 1, 3)] : (waiting ? 10 : 3)
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            guard isScreenActive else { return }
            await load()
            if errorMessage == nil { consecutiveErrors = 0 } else { consecutiveErrors = min(consecutiveErrors + 1, 4) }
        }
    }

    private func startPollingIfNeeded() {
        guard isMonitoring, isScreenActive, pollingTask == nil, hasActiveWork else { return }
        pollingTask = Task { [weak self] in
            await self?.pollActiveJobs()
        }
    }

    private var hasActiveWork: Bool {
        jobs.contains {
            $0.status == .queued || $0.status == .processing || $0.isAssetRetryInFlight
        } || queueReceipts.contains {
            [.preparing, .queued, .active, .draining, .retryWaiting].contains($0.state)
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
            startPollingIfNeeded()
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

    func retryDiscoveryAfterExtractionFix() async {
        guard let discoveryResult,
              discoveryResult.canRetryExtractionAfterFix else { return }
        await mutateDiscovery(errorText: "시즌 목록을 다시 가져오지 못했습니다.") {
            self.discoveryResult = try await self.discoveryRepository
                .retrySeasonDiscoveryAfterExtractionFix(
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
