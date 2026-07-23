import Foundation

protocol ManageLookbookExtractionReviewUseCaseProtocol {
    func load(
        brandID: BrandID,
        jobID: String
    ) async throws -> LookbookExtractionReview

    func approve(
        brandID: BrandID,
        review: LookbookExtractionReview,
        excludedCandidateKeys: [String]
    ) async throws -> LookbookExtractionReviewReceipt

    func reportInsufficientImages(
        brandID: BrandID,
        review: LookbookExtractionReview,
        expectedCandidateCount: Int?,
        note: String?
    ) async throws -> LookbookExtractionReviewReceipt

    func reanalyze(
        brandID: BrandID,
        jobID: String
    ) async throws -> LookbookExtractionReviewReceipt
}

final class ManageLookbookExtractionReviewUseCase:
    ManageLookbookExtractionReviewUseCaseProtocol {
    private let repository: any LookbookExtractionReviewRepositoryProtocol

    init(repository: any LookbookExtractionReviewRepositoryProtocol) {
        self.repository = repository
    }

    func load(
        brandID: BrandID,
        jobID: String
    ) async throws -> LookbookExtractionReview {
        try await repository.loadReview(brandID: brandID, jobID: jobID)
    }

    func approve(
        brandID: BrandID,
        review: LookbookExtractionReview,
        excludedCandidateKeys: [String]
    ) async throws -> LookbookExtractionReviewReceipt {
        try await repository.submitReview(
            brandID: brandID,
            review: review,
            decision: excludedCandidateKeys.isEmpty
                ? .approved
                : .approvedWithExclusions,
            excludedCandidateKeys: excludedCandidateKeys,
            expectedCandidateCount: nil,
            note: nil
        )
    }

    func reportInsufficientImages(
        brandID: BrandID,
        review: LookbookExtractionReview,
        expectedCandidateCount: Int?,
        note: String?
    ) async throws -> LookbookExtractionReviewReceipt {
        try await repository.submitReview(
            brandID: brandID,
            review: review,
            decision: .insufficientImages,
            excludedCandidateKeys: [],
            expectedCandidateCount: expectedCandidateCount,
            note: note
        )
    }

    func reanalyze(
        brandID: BrandID,
        jobID: String
    ) async throws -> LookbookExtractionReviewReceipt {
        try await repository.requestReanalysis(brandID: brandID, jobID: jobID)
    }
}
