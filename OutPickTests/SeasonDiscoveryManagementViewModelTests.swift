import FirebaseFirestore
import Foundation
import Testing
@testable import OutPick

@MainActor
struct SeasonDiscoveryManagementViewModelTests {
    @Test func improvementReadyRequiresRevisionHigherThanBlockedRevision() {
        let result = SeasonCandidateDiscoveryResult(
            brandID: BrandID(value: "brand-1"),
            jobID: "job-1",
            generation: 1,
            status: .correctionRequired,
            sourceURL: "https://example.com/lookbooks",
            candidateCount: 1,
            candidateSnapshotHash: "snapshot",
            recommendedAction: "reanalyzeWithNewVersion",
            improvementRequested: true,
            blockedByExtractionContractRevision: 1,
            availableExtractionContractRevision: 2
        )

        #expect(result.improvementState == .ready)
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

    @Test func improvementRequestImmediatelyMarksCurrentResultAsRequested() async {
        let repository = SeasonDiscoveryRepositoryFake()
        repository.observedResults = [makeResult(status: .correctionRequired)]
        let viewModel = SeasonImportManagementViewModel(
            brandID: BrandID(value: "brand-1"),
            useCase: SeasonImportManagementUseCaseFake(),
            discoveryRepository: repository
        )
        await viewModel.monitor()

        await viewModel.requestDiscoveryImprovement()

        #expect(repository.improvementRequestedJobIDs == ["job-1"])
        #expect(viewModel.discoveryResult?.improvementState == .requested)
        #expect(viewModel.presentedErrorMessage == nil)
    }

    @Test func reanalysisReplacesCorrectionResultWithNewQueuedGeneration() async {
        let repository = SeasonDiscoveryRepositoryFake()
        repository.observedResults = [makeResult(status: .correctionRequired)]
        repository.reanalysisResult = SeasonCandidateDiscoveryResult(
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

        await viewModel.reanalyzeDiscovery()

        #expect(repository.reanalyzedJobIDs == ["job-1"])
        #expect(viewModel.discoveryResult?.jobID == "job-2")
        #expect(viewModel.discoveryResult?.status == .queued)
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
        candidateCount: Int = 0
    ) -> SeasonCandidateDiscoveryResult {
        SeasonCandidateDiscoveryResult(
            brandID: BrandID(value: "brand-1"),
            jobID: "job-1",
            generation: 1,
            status: status,
            sourceURL: "https://example.com/lookbooks",
            candidateCount: candidateCount,
            candidateSnapshotHash: "snapshot",
            phase: phase
        )
    }
}

private final class SeasonImportManagementUseCaseFake:
    ManageSeasonImportJobsUseCaseProtocol {
    func loadJobs(brandID: BrandID) async throws -> [SeasonImportJob] { [] }

    func retryAssets(
        brandID: BrandID,
        sourceJobID: String
    ) async throws -> SeasonAssetRetryReceipt {
        throw NSError(domain: "unused", code: -1)
    }
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
    var improvementRequestedJobIDs: [String] = []
    var reanalyzedJobIDs: [String] = []
    var reanalysisResult: SeasonCandidateDiscoveryResult?
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
        requestResult
    }

    func observeSeasonDiscovery(
        brandID: BrandID,
        jobID: String
    ) async throws -> SeasonCandidateDiscoveryResult {
        requestResult
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

    func requestSeasonDiscoveryImprovement(
        brandID: BrandID,
        job: SeasonCandidateDiscoveryResult
    ) async throws {
        improvementRequestedJobIDs.append(job.jobID)
    }

    func reanalyzeSeasonDiscoveryWithLatestExtractor(
        brandID: BrandID,
        job: SeasonCandidateDiscoveryResult
    ) async throws -> SeasonCandidateDiscoveryResult {
        reanalyzedJobIDs.append(job.jobID)
        return reanalysisResult ?? requestResult
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
