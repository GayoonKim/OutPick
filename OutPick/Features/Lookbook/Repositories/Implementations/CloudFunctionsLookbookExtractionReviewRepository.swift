import Foundation

struct CloudFunctionsLookbookExtractionReviewRepository:
    LookbookExtractionReviewRepositoryProtocol {
    private let transport: any CloudFunctionsTransporting

    init(transport: any CloudFunctionsTransporting = FirebaseCloudFunctionsTransport()) {
        self.transport = transport
    }

    func loadReview(
        brandID: BrandID,
        jobID: String
    ) async throws -> LookbookExtractionReview {
        let response = try await transport.call(
            "getLookbookExtractionReview",
            data: ["brandID": brandID.value, "jobID": jobID]
        )
        return try LookbookExtractionReviewCloudFunctionsMapper.review(response)
    }

    func submitReview(
        brandID: BrandID,
        review: LookbookExtractionReview,
        decision: LookbookExtractionReviewDecision,
        excludedCandidateKeys: [String],
        expectedCandidateCount: Int?,
        note: String?
    ) async throws -> LookbookExtractionReviewReceipt {
        var data: [String: Any] = [
            "brandID": brandID.value,
            "jobID": review.jobID,
            "reviewGeneration": review.reviewGeneration,
            "reviewSnapshotHash": review.reviewSnapshotHash,
            "decision": decision.rawValue,
            "excludedCandidateKeys": excludedCandidateKeys
        ]
        if let expectedCandidateCount {
            data["expectedCandidateCount"] = expectedCandidateCount
        }
        if let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            data["note"] = note
        }
        let response = try await transport.call(
            "reviewLookbookExtraction",
            data: data
        )
        return try LookbookExtractionReviewCloudFunctionsMapper.receipt(response)
    }

    func requestReanalysis(
        brandID: BrandID,
        jobID: String
    ) async throws -> LookbookExtractionReviewReceipt {
        let response = try await transport.call(
            "requestLookbookExtractionReanalysis",
            data: ["brandID": brandID.value, "jobID": jobID]
        )
        return try LookbookExtractionReviewCloudFunctionsMapper.receipt(response)
    }
}
