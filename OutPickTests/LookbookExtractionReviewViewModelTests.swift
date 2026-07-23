import Foundation
import Testing
@testable import OutPick

@MainActor
struct LookbookExtractionReviewViewModelTests {
    @Test func excludesCandidateAndApprovesThroughUseCase() async {
        let repository = ExtractionReviewRepositoryFake()
        let review = makeReview()
        repository.review = review
        var completed = false
        let viewModel = LookbookExtractionReviewViewModel(
            brandID: review.brandID,
            jobID: review.jobID,
            useCase: ManageLookbookExtractionReviewUseCase(repository: repository),
            onCompleted: { completed = true }
        )

        await viewModel.load()
        viewModel.toggle(candidateKey: "candidate-1")
        await viewModel.approve()

        #expect(repository.submittedDecision == .approvedWithExclusions)
        #expect(repository.submittedExcludedKeys == ["candidate-1"])
        #expect(completed)
    }

    @Test func insufficientImagesStaysOnReviewAndReloads() async {
        let repository = ExtractionReviewRepositoryFake()
        repository.review = makeReview(expectedCounts: [45])
        let viewModel = LookbookExtractionReviewViewModel(
            brandID: BrandID(value: "brand-1"),
            jobID: "job-1",
            useCase: ManageLookbookExtractionReviewUseCase(repository: repository),
            onCompleted: {}
        )
        await viewModel.load()
        viewModel.expectedCandidateCountText = "45"
        await viewModel.reportInsufficientImages()

        #expect(repository.submittedDecision == .insufficientImages)
        #expect(repository.submittedExpectedCount == 45)
        #expect(repository.loadCount == 2)
    }

    @Test func fewerCandidatesPrefillsExpectedCountAndBlocksApproval() async {
        let repository = ExtractionReviewRepositoryFake()
        let review = makeReview(expectedCounts: [24])
        repository.review = review
        var completed = false
        let viewModel = LookbookExtractionReviewViewModel(
            brandID: review.brandID,
            jobID: review.jobID,
            useCase: ManageLookbookExtractionReviewUseCase(repository: repository),
            onCompleted: { completed = true }
        )

        await viewModel.load()
        #expect(viewModel.expectedCandidateCountText == "24")
        #expect(viewModel.canReportInsufficientImages)

        await viewModel.approve()
        #expect(repository.submittedDecision == nil)
        #expect(!completed)
    }

    @Test func unknownExpectedCountAllowsApprovalAndRequiresCountForShortage() async {
        let repository = ExtractionReviewRepositoryFake()
        let review = makeReview(expectedCounts: [])
        repository.review = review
        let viewModel = LookbookExtractionReviewViewModel(
            brandID: review.brandID,
            jobID: review.jobID,
            useCase: ManageLookbookExtractionReviewUseCase(repository: repository),
            onCompleted: {}
        )

        await viewModel.load()
        #expect(review.allowsApproval)
        #expect(review.showsInsufficientImagesForm)
        #expect(!viewModel.canReportInsufficientImages)

        viewModel.expectedCandidateCountText = "2"
        #expect(viewModel.canReportInsufficientImages)
    }

    @Test func contentIntegrityIssueBlocksApprovalAndShortageReport() async {
        let repository = ExtractionReviewRepositoryFake()
        let review = makeReview(
            expectedCounts: [1],
            qualityReasons: ["content_hash_incomplete"]
        )
        repository.review = review
        let viewModel = LookbookExtractionReviewViewModel(
            brandID: review.brandID,
            jobID: review.jobID,
            useCase: ManageLookbookExtractionReviewUseCase(repository: repository),
            onCompleted: {}
        )

        await viewModel.load()
        await viewModel.approve()
        viewModel.expectedCandidateCountText = "2"
        await viewModel.reportInsufficientImages()

        #expect(repository.submittedDecision == nil)
        #expect(!review.allowsApproval)
        #expect(!review.showsInsufficientImagesForm)
    }

    @Test func loadFailureCanRetryWithoutRecreatingViewModel() async {
        let repository = ExtractionReviewRepositoryFake()
        repository.review = makeReview()
        repository.shouldFailLoad = true
        let viewModel = LookbookExtractionReviewViewModel(
            brandID: BrandID(value: "brand-1"),
            jobID: "job-1",
            useCase: ManageLookbookExtractionReviewUseCase(repository: repository),
            onCompleted: {}
        )

        await viewModel.load()
        #expect(viewModel.review == nil)
        #expect(viewModel.errorMessage == "검토 정보를 불러오지 못했습니다.")
        #expect(!viewModel.isLoading)

        repository.shouldFailLoad = false
        await viewModel.load()
        #expect(viewModel.review?.jobID == "job-1")
        #expect(viewModel.errorMessage == nil)
        #expect(repository.loadCount == 2)
    }

    @Test func approvalFailureKeepsReviewForRetry() async {
        let repository = ExtractionReviewRepositoryFake()
        repository.review = makeReview()
        repository.shouldFailSubmit = true
        var completed = false
        let viewModel = LookbookExtractionReviewViewModel(
            brandID: BrandID(value: "brand-1"),
            jobID: "job-1",
            useCase: ManageLookbookExtractionReviewUseCase(repository: repository),
            onCompleted: { completed = true }
        )

        await viewModel.load()
        await viewModel.approve()
        #expect(viewModel.errorMessage == "검토 결과를 승인하지 못했습니다.")
        #expect(!viewModel.isSubmitting)
        #expect(!completed)

        repository.shouldFailSubmit = false
        await viewModel.approve()
        #expect(viewModel.errorMessage == nil)
        #expect(completed)
    }

    private func makeReview(
        expectedCounts: [Int] = [0],
        qualityReasons: [String] = ["expected_count_mismatch"]
    ) -> LookbookExtractionReview {
        LookbookExtractionReview(
            jobID: "job-1",
            brandID: BrandID(value: "brand-1"),
            status: .awaitingReview,
            reviewStatus: .pending,
            reviewGeneration: 1,
            reviewSnapshotHash: "snapshot",
            qualityReasons: qualityReasons,
            expectedCandidateCounts: expectedCounts,
            candidates: [
                LookbookExtractionReviewCandidate(
                    candidateKey: "candidate-1",
                    sourceURL: URL(string: "https://example.com/1.jpg")!,
                    alt: nil
                )
            ],
            canReanalyze: false
        )
    }
}

@MainActor
private final class ExtractionReviewRepositoryFake:
    LookbookExtractionReviewRepositoryProtocol {
    private enum Failure: Error {
        case requested
    }

    var review: LookbookExtractionReview!
    var loadCount = 0
    var shouldFailLoad = false
    var shouldFailSubmit = false
    var submittedDecision: LookbookExtractionReviewDecision?
    var submittedExcludedKeys: [String] = []
    var submittedExpectedCount: Int?

    func loadReview(
        brandID: BrandID,
        jobID: String
    ) async throws -> LookbookExtractionReview {
        loadCount += 1
        if shouldFailLoad {
            throw Failure.requested
        }
        return review
    }

    func submitReview(
        brandID: BrandID,
        review: LookbookExtractionReview,
        decision: LookbookExtractionReviewDecision,
        excludedCandidateKeys: [String],
        expectedCandidateCount: Int?,
        note: String?
    ) async throws -> LookbookExtractionReviewReceipt {
        if shouldFailSubmit {
            throw Failure.requested
        }
        submittedDecision = decision
        submittedExcludedKeys = excludedCandidateKeys
        submittedExpectedCount = expectedCandidateCount
        return LookbookExtractionReviewReceipt(status: "queued", duplicate: false)
    }

    func requestReanalysis(
        brandID: BrandID,
        jobID: String
    ) async throws -> LookbookExtractionReviewReceipt {
        LookbookExtractionReviewReceipt(status: "queued", duplicate: false)
    }
}
