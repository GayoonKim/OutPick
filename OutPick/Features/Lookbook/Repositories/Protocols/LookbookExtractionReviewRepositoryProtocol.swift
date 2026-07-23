import Foundation

protocol LookbookExtractionReviewRepositoryProtocol {
    func loadReview(
        brandID: BrandID,
        jobID: String
    ) async throws -> LookbookExtractionReview

    func submitReview(
        brandID: BrandID,
        review: LookbookExtractionReview,
        decision: LookbookExtractionReviewDecision,
        excludedCandidateKeys: [String],
        expectedCandidateCount: Int?,
        note: String?
    ) async throws -> LookbookExtractionReviewReceipt

    func requestReanalysis(
        brandID: BrandID,
        jobID: String
    ) async throws -> LookbookExtractionReviewReceipt
}
