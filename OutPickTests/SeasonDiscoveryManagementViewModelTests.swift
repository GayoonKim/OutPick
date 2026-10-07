import FirebaseFirestore
import Foundation
import Testing
@testable import OutPick

@MainActor
struct SeasonDiscoveryManagementViewModelTests {
    @Test func createBrandDiscoveryFailureHidesInfrastructureError() async throws {
        let infrastructureMessage = "Missing or insufficient permissions."
        let repository = SeasonDiscoveryRepositoryFake()
        repository.discoveryError = NSError(
            domain: "FIRFirestoreErrorDomain",
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: infrastructureMessage]
        )
        let viewModel = CreateBrandDiscoveryViewModel(repository: repository)

        viewModel.start(brandID: BrandID(value: "brand-1"))
        try await waitUntil { viewModel.errorMessage != nil }

        #expect(
            viewModel.errorMessage ==
                "시즌 목록을 불러오지 못했어요. 브랜드 등록을 마친 뒤 다시 찾아올 수 있어요."
        )
        #expect(viewModel.errorMessage?.contains(infrastructureMessage) == false)
        #expect(viewModel.result == nil)
    }

    @Test func createBrandDiscoverySuccessPublishesResultWithoutError() async throws {
        let repository = SeasonDiscoveryRepositoryFake()
        let viewModel = CreateBrandDiscoveryViewModel(repository: repository)

        viewModel.start(
            brandID: BrandID(value: "brand-1"),
            existingJobID: "job-1"
        )
        try await waitUntil { viewModel.result != nil }

        #expect(viewModel.result?.jobID == "job-1")
        #expect(viewModel.errorMessage == nil)
    }

    @Test func extractionIssueStatusMapsToThreeUserStatesAndWontFix() {
        let base = SeasonCandidateDiscoveryResult(
            brandID: BrandID(value: "brand-1"),
            jobID: "job-1",
            generation: 1,
            status: .correctionRequired,
            sourceURL: "https://example.com/lookbooks",
            candidateCount: 1,
            candidateSnapshotHash: "snapshot",
            extractionIssueStatus: .open
        )
        #expect(base.extractionIssueUserState == .waiting)
        #expect(makeResult(status: .correctionRequired, issueStatus: .inProgress)
            .extractionIssueUserState == .processing)
        #expect(makeResult(status: .correctionRequired, issueStatus: .needsGroundTruth)
            .extractionIssueUserState == .processing)
        #expect(makeResult(
            status: .correctionRequired,
            issueStatus: .fixed,
            retryRuntime: "contract:2"
        ).canRetryExtractionAfterFix)
        #expect(makeResult(status: .correctionRequired, issueStatus: .wontFix)
            .extractionIssueUserState == .wontFix)
    }

    @Test func monitorReflectsLatestDiscoveryStateUntilCompletion() async {
        let repository = SeasonDiscoveryRepositoryFake()
        repository.observedResults = [
            makeResult(status: .running, phase: "parsing"),
            makeResult(status: .succeeded, candidateCount: 3)
        ]
        let viewModel = SeasonImportManagementViewModel(
            brandID: BrandID(value: "brand-1"),
            useCase: SeasonImportManagementUseCaseFake(),
            discoveryRepository: repository
        )

        await viewModel.monitor()

        #expect(viewModel.discoveryResult?.status == .succeeded)
        #expect(viewModel.discoveryResult?.candidateCount == 3)
        #expect(repository.latestObservationCount == 1)
    }

    @Test func requestRetryAndCancelUseCurrentJobWithoutDuplicateMutation() async {
        let repository = SeasonDiscoveryRepositoryFake()
        repository.requestResult = makeResult(status: .queued)
        let viewModel = SeasonImportManagementViewModel(
            brandID: BrandID(value: "brand-1"),
            useCase: SeasonImportManagementUseCaseFake(),
            discoveryRepository: repository
        )

        await viewModel.requestDiscovery()
        await viewModel.retryDiscovery()
        await viewModel.cancelDiscovery()

        #expect(viewModel.discoveryResult?.jobID == "job-1")
        #expect(repository.requestCount == 1)
        #expect(repository.retriedJobIDs == ["job-1"])
        #expect(repository.cancelledJobIDs == ["job-1"])
        #expect(viewModel.presentedErrorMessage == nil)
        #expect(!viewModel.isMutatingDiscovery)
    }

    @Test func fixedRetryReplacesCorrectionResultWithNewQueuedGeneration() async {
        let repository = SeasonDiscoveryRepositoryFake()
        repository.observedResults = [makeResult(
            status: .correctionRequired,
            issueStatus: .fixed,
            retryRuntime: "contract:2"
        )]
        repository.fixedRetryResult = SeasonCandidateDiscoveryResult(
            brandID: BrandID(value: "brand-1"),
            jobID: "job-2",
            generation: 2,
            status: .queued,
            sourceURL: "https://example.com/lookbooks",
            candidateCount: 0,
            candidateSnapshotHash: nil
        )
        let viewModel = SeasonImportManagementViewModel(
            brandID: BrandID(value: "brand-1"),
            useCase: SeasonImportManagementUseCaseFake(),
            discoveryRepository: repository
        )
        await viewModel.monitor()

        await viewModel.retryDiscoveryAfterExtractionFix()

        #expect(repository.fixedRetryJobIDs == ["job-1"])
        #expect(viewModel.discoveryResult?.jobID == "job-2")
        #expect(viewModel.discoveryResult?.status == .queued)
    }

    @Test func retryAfterFixIsIgnoredUntilFixedRuntimeIsAvailable() async {
        let repository = SeasonDiscoveryRepositoryFake()
        repository.observedResults = [makeResult(
            status: .correctionRequired,
            issueStatus: .inProgress
        )]
        let viewModel = SeasonImportManagementViewModel(
            brandID: BrandID(value: "brand-1"),
            useCase: SeasonImportManagementUseCaseFake(),
            discoveryRepository: repository
        )
        await viewModel.monitor()

        await viewModel.retryDiscoveryAfterExtractionFix()

        #expect(repository.fixedRetryJobIDs.isEmpty)
    }

    @Test func assetRetryReturnsWithoutWaitingForQueuedBatchToFinish() async throws {
        let job = SeasonImportJob(
            id: "job-1",
            brandID: BrandID(value: "brand-1"),
            jobType: .importSeasonFromURL,
            status: .partialFailed,
            phase: .completed,
            sourceURL: "https://example.com/season",
            seasonTitle: "2026 SS",
            sourceTitle: nil,
            sourceCandidateID: nil,
            sourceImportJobID: nil,
            targetSeasonID: SeasonID(value: "season-1"),
            requestedBy: "user-1",
            errorMessage: nil,
            assetRetryStatus: nil,
            assetCompletedCount: 2,
            assetFailedCount: 1,
            reviewStatus: nil,
            reviewGeneration: 0,
            repairStatus: nil,
            repairGeneration: 0,
            extractionQualityReasons: [],
            extractionIssueStatus: nil,
            retryAvailableRuntimeVersion: nil,
            extractionIssueWontFixReason: nil,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let useCase = SeasonImportManagementUseCaseFake(jobs: [job])
        let queueUseCase = SeasonImportQueueUseCaseFake(receipts: [queuedReceipt()])
        let viewModel = SeasonImportManagementViewModel(
            brandID: BrandID(value: "brand-1"),
            useCase: useCase,
            discoveryRepository: SeasonDiscoveryRepositoryFake(),
            queueUseCase: queueUseCase
        )
        await viewModel.load()
        var didFinish = false
        let retryTask = Task { @MainActor in
            await viewModel.retryAssets(for: job)
            didFinish = true
        }
        defer { retryTask.cancel() }

        try await waitUntil { didFinish }

        #expect(useCase.loadCount == 2)
        #expect(viewModel.retryingJobID == nil)
    }

    @Test func reviewResolutionRemovesCandidateAndCompletesOnlyWhenEmpty() async throws {
        let repository = SeasonDiscoveryRepositoryFake()
        repository.reviewCandidates = [
            SeasonDiscoveryReviewCandidate(
                id: "candidate-1",
                title: "25 F/W",
                seasonURL: "https://example.com/fw25",
                coverImageURL: nil,
                resolution: "awaitingReviewAmbiguousTitle",
                matchedSeasonID: nil
            )
        ]
        var completed = false
        let viewModel = SeasonDiscoveryReviewViewModel(
            job: makeResult(status: .awaitingReview),
            repository: repository,
            seasonRepository: SeasonRepositoryFake(),
            onCompleted: { completed = true }
        )

        await viewModel.load()
        let candidate = try #require(viewModel.candidates.first)
        await viewModel.keepAsNew(candidate)

        #expect(viewModel.candidates.isEmpty)
        #expect(completed)
        #expect(repository.resolutions.map(\.decision) == ["keepAsNew"])
    }

    @Test func failedReviewResolutionPreservesCandidateForRetry() async throws {
        let repository = SeasonDiscoveryRepositoryFake()
        repository.reviewCandidates = [
            SeasonDiscoveryReviewCandidate(
                id: "candidate-1",
                title: "Archive",
                seasonURL: "https://example.com/archive",
                coverImageURL: nil,
                resolution: "awaitingReviewAmbiguousTitle",
                matchedSeasonID: nil
            )
        ]
        repository.shouldFailResolution = true
        var completed = false
        let viewModel = SeasonDiscoveryReviewViewModel(
            job: makeResult(status: .awaitingReview),
            repository: repository,
            seasonRepository: SeasonRepositoryFake(),
            onCompleted: { completed = true }
        )

        await viewModel.load()
        let candidate = try #require(viewModel.candidates.first)
        await viewModel.reject(candidate)

        #expect(viewModel.candidates.map(\.id) == ["candidate-1"])
        #expect(viewModel.errorMessage != nil)
        #expect(!completed)
    }

    private func makeResult(
        status: SeasonDiscoveryJobStatus,
        phase: String? = nil,
        candidateCount: Int = 0,
        issueStatus: ExtractionIssueStatus? = nil,
        retryRuntime: String? = nil
    ) -> SeasonCandidateDiscoveryResult {
        SeasonCandidateDiscoveryResult(
            brandID: BrandID(value: "brand-1"),
            jobID: "job-1",
            generation: 1,
            status: status,
            sourceURL: "https://example.com/lookbooks",
            candidateCount: candidateCount,
            candidateSnapshotHash: "snapshot",
            phase: phase,
            extractionIssueStatus: issueStatus,
            retryAvailableRuntimeVersion: retryRuntime
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        _ predicate: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while predicate() == false && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(predicate())
    }
}

private final class SeasonImportManagementUseCaseFake:
    ManageSeasonImportJobsUseCaseProtocol {
    private let jobs: [SeasonImportJob]
    private(set) var loadCount = 0

    init(jobs: [SeasonImportJob] = []) {
        self.jobs = jobs
    }

    func loadJobs(brandID: BrandID) async throws -> [SeasonImportJob] {
        loadCount += 1
        return jobs
    }

    func retryAssets(
        brandID: BrandID,
        sourceJobID: String
    ) async throws -> SeasonAssetRetryReceipt {
        SeasonAssetRetryReceipt(
            sourceImportJobID: sourceJobID,
            seasonID: "season-1",
            status: "queued",
            isDuplicate: false
        )
    }
}

private struct SeasonImportQueueUseCaseFake: StartSeasonImportExtractionUseCaseProtocol {
    let receipts: [LookbookImportQueueReceipt]

    func execute(
        brandID: BrandID,
        candidates: [SeasonCandidate]
    ) async throws -> LookbookImportQueueReceipt {
        guard let receipt = receipts.first else { throw NSError(domain: "unused", code: -1) }
        return receipt
    }

    func loadProgress(requestID: String) async throws -> SeasonImportExtractionProgress {
        throw NSError(domain: "unused", code: -1)
    }

    func reconcileUnsettledRequests(brandID: BrandID) async throws -> [LookbookImportQueueReceipt] {
        receipts
    }

    func latestUnsettledRequestID(brandID: BrandID) async throws -> String? {
        receipts.first?.requestID
    }

    func unsettledRequestID(brandID: BrandID, candidates: [SeasonCandidate]) async throws -> String? {
        receipts.first?.requestID
    }
}

private func queuedReceipt() -> LookbookImportQueueReceipt {
    LookbookImportQueueReceipt(
        contractVersion: 1,
        requestID: "123e4567-e89b-42d3-a456-426614174000",
        batchID: String(repeating: "a", count: 64),
        brandID: "brand-1",
        kind: "importSeasons",
        state: .queued,
        stateRevision: 1,
        items: [
            LookbookImportQueueReceipt.Item(
                itemID: "item-1",
                targetID: "candidate-1",
                ordinal: 0,
                admissionStatus: "created",
                processingStatus: "queued",
                jobID: "job-1",
                executionID: "execution-1",
                errorCode: nil
            )
        ]
    )
}

private final class SeasonDiscoveryRepositoryFake:
    SeasonCandidateDiscoveryRepositoryProtocol {
    struct Resolution: Equatable {
        let candidateID: String
        let decision: String
        let targetSeasonID: SeasonID?
    }

    var requestResult = SeasonCandidateDiscoveryResult(
        brandID: BrandID(value: "brand-1"),
        jobID: "job-1",
        generation: 1,
        status: .queued,
        sourceURL: "https://example.com/lookbooks",
        candidateCount: 0,
        candidateSnapshotHash: nil
    )
    var observedResults: [SeasonCandidateDiscoveryResult?] = []
    var reviewCandidates: [SeasonDiscoveryReviewCandidate] = []
    var requestCount = 0
    var latestObservationCount = 0
    var retriedJobIDs: [String] = []
    var cancelledJobIDs: [String] = []
    var fixedRetryJobIDs: [String] = []
    var fixedRetryResult: SeasonCandidateDiscoveryResult?
    var discoveryError: Error?
    var resolutions: [Resolution] = []
    var shouldFailResolution = false

    func requestSeasonDiscovery(
        brandID: BrandID
    ) async throws -> SeasonCandidateDiscoveryResult {
        requestCount += 1
        return requestResult
    }

    func discoverSeasonCandidates(
        brandID: BrandID
    ) async throws -> SeasonCandidateDiscoveryResult {
        if let discoveryError {
            throw discoveryError
        }
        return requestResult
    }

    func observeSeasonDiscovery(
        brandID: BrandID,
        jobID: String
    ) async throws -> SeasonCandidateDiscoveryResult {
        if let discoveryError {
            throw discoveryError
        }
        return requestResult
    }

    func observeLatestSeasonDiscovery(
        brandID: BrandID
    ) -> AsyncThrowingStream<SeasonCandidateDiscoveryResult?, Error> {
        latestObservationCount += 1
        let results = observedResults
        return AsyncThrowingStream { continuation in
            results.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }

    func retrySeasonDiscovery(brandID: BrandID, jobID: String) async throws {
        retriedJobIDs.append(jobID)
    }

    func cancelSeasonDiscovery(brandID: BrandID, jobID: String) async throws {
        cancelledJobIDs.append(jobID)
    }

    func retrySeasonDiscoveryAfterExtractionFix(
        brandID: BrandID,
        job: SeasonCandidateDiscoveryResult
    ) async throws -> SeasonCandidateDiscoveryResult {
        fixedRetryJobIDs.append(job.jobID)
        return fixedRetryResult ?? requestResult
    }

    func fetchReviewCandidates(
        brandID: BrandID,
        jobID: String
    ) async throws -> [SeasonDiscoveryReviewCandidate] {
        reviewCandidates
    }

    func resolveReviewCandidate(
        brandID: BrandID,
        job: SeasonCandidateDiscoveryResult,
        candidateID: String,
        decision: String,
        targetSeasonID: SeasonID?
    ) async throws {
        if shouldFailResolution {
            throw NSError(domain: "requested", code: -1)
        }
        resolutions.append(
            Resolution(
                candidateID: candidateID,
                decision: decision,
                targetSeasonID: targetSeasonID
            )
        )
    }
}

private struct SeasonRepositoryFake: SeasonRepositoryProtocol {
    func fetchSeason(brandID: BrandID, seasonID: SeasonID) async throws -> Season {
        throw NSError(domain: "unused", code: -1)
    }

    func fetchSeasons(
        brandID: BrandID,
        pageSize: Int,
        after last: DocumentSnapshot?
    ) async throws -> SeasonPage {
        throw NSError(domain: "unused", code: -1)
    }

    func fetchAllSeasons(brandID: BrandID) async throws -> [Season] { [] }
}
