import Foundation

enum LookbookExtractionDiagnosticType: String, Codable, Equatable {
    case seasonDiscovery = "season_discovery"
    case seasonImageImport = "season_image_import"
}

enum LookbookExtractionDiagnosticStatus: String, Codable, Equatable {
    case passed
    case failed
    case needsReview
}

enum LookbookExtractionSuggestedFixScope: String, Codable, Equatable {
    case commonLogic = "common_logic"
    case brandAdapter = "brand_adapter"
    case unknown
}

enum LookbookExtractionFailureReason: String, Codable, Equatable {
    case archiveURLMissing = "archive_url_missing"
    case archiveURLFetchFailed = "archive_url_fetch_failed"
    case noCandidatesFound = "no_candidates_found"
    case lowConfidenceCandidates = "low_confidence_candidates"
    case loadMoreDetected = "load_more_detected"
    case dynamicRenderingDetected = "dynamic_rendering_detected"
    case workerTimeout = "worker_timeout"
    case workerFailed = "worker_failed"
    case imageLoadFailed = "image_load_failed"
    case assetSyncFailed = "asset_sync_failed"
    case permissionDenied = "permission_denied"
    case unknown
}

struct LookbookExtractionSuggestedFix: Equatable, Codable {
    let type: String
    let scope: LookbookExtractionSuggestedFixScope
    let confidence: Double
    let message: String
}

struct SeasonDiscoveryDiagnosticDetail: Equatable, Codable {
    let staticCandidateCount: Int
    let renderedCandidateCount: Int?
    let candidateCountBeforeExpansion: Int
    let candidateCountAfterExpansion: Int
    let storedCandidateCount: Int
    let diagnosticCandidateCount: Int
    let loadMoreDetected: Bool
    let loadMoreClickCount: Int
    let infiniteScrollAttempted: Bool
    let scrollAttemptCount: Int
    let dynamicRenderingDetected: Bool
    let renderedFallbackUsed: Bool
    let parserStrategy: String
    let adapterKey: String?
}

struct SeasonImageImportDiagnosticDetail: Equatable, Codable {
    let sourceImportJobID: String
    let targetSeasonID: String?
    let seasonTitle: String?
    let expectedImageCount: Int
    let importedImageCount: Int
    let failedImageCount: Int
    let retryable: Bool
}

struct LookbookExtractionDiagnostic: Equatable, Identifiable, Codable {
    let id: String
    let brandID: BrandID
    let type: LookbookExtractionDiagnosticType
    let status: LookbookExtractionDiagnosticStatus
    let sourceURL: String?
    let summaryMessage: String?
    let errorMessage: String?
    let failureReasons: [LookbookExtractionFailureReason]
    let suggestedFixScope: LookbookExtractionSuggestedFixScope
    let suggestedFixes: [LookbookExtractionSuggestedFix]
    let seasonDiscovery: SeasonDiscoveryDiagnosticDetail?
    let seasonImageImport: SeasonImageImportDiagnosticDetail?
    let createdAt: Date?
    let updatedAt: Date?
    let completedAt: Date?
    let expiresAt: Date?
}
