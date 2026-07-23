import Foundation

struct LookbookExtractionReviewCandidate: Equatable, Identifiable {
    let candidateKey: String
    let sourceURL: URL
    let alt: String?

    var id: String { candidateKey }
}

struct LookbookExtractionReview: Equatable {
    let jobID: String
    let brandID: BrandID
    let status: SeasonImportJobStatus
    let reviewStatus: SeasonImportReviewStatus
    let reviewGeneration: Int
    let reviewSnapshotHash: String
    let qualityReasons: [String]
    let expectedCandidateCounts: [Int]
    let candidates: [LookbookExtractionReviewCandidate]
    let canReanalyze: Bool

    var isCorrectionRequired: Bool {
        reviewStatus == .correctionRequired
    }
}

enum LookbookExtractionReviewDecision: String {
    case approved
    case approvedWithExclusions
    case insufficientImages
}

struct LookbookExtractionReviewReceipt: Equatable {
    let status: String
    let duplicate: Bool
}
