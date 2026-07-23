import Foundation

struct LookbookExtractionReviewCandidate: Equatable, Identifiable {
    let candidateKey: String
    let sourceURL: URL
    let alt: String?

    var id: String { candidateKey }
}

struct LookbookExtractionReview: Equatable {
    enum CandidateCountComparison: Equatable {
        case unknown
        case matches(expected: Int)
        case extractedMore(expected: Int)
        case extractedFewer(expected: Int)
    }

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

    var expectedCandidateCount: Int? {
        if expectedCandidateCounts.contains(candidates.count) {
            return candidates.count
        }
        return expectedCandidateCounts.max()
    }

    var candidateCountComparison: CandidateCountComparison {
        guard let expectedCandidateCount else {
            return .unknown
        }
        if candidates.count == expectedCandidateCount {
            return .matches(expected: expectedCandidateCount)
        }
        if candidates.count > expectedCandidateCount {
            return .extractedMore(expected: expectedCandidateCount)
        }
        return .extractedFewer(expected: expectedCandidateCount)
    }

    var hasContentIntegrityIssue: Bool {
        qualityReasons.contains("content_hash_incomplete")
    }

    var allowsCandidateExclusion: Bool {
        guard !isCorrectionRequired, !hasContentIntegrityIssue else {
            return false
        }
        switch candidateCountComparison {
        case .unknown, .extractedMore:
            return true
        case .matches, .extractedFewer:
            return false
        }
    }

    var allowsApproval: Bool {
        guard !isCorrectionRequired, !hasContentIntegrityIssue else {
            return false
        }
        if case .extractedFewer = candidateCountComparison {
            return false
        }
        return true
    }

    var showsInsufficientImagesForm: Bool {
        switch candidateCountComparison {
        case .unknown, .extractedFewer:
            return !isCorrectionRequired && !hasContentIntegrityIssue
        case .matches, .extractedMore:
            return false
        }
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
