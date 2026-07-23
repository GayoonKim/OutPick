import Foundation
import Testing
@testable import OutPick

struct SeasonImportJobRepairStateTests {
    @Test func noChangesIsCompletedAndCanCompareAgain() {
        let job = makeJob(
            status: .succeeded,
            repairStatus: .noChanges
        )

        #expect(job.canRequestSeasonRepair)
        #expect(!job.needsSeasonRepairPreview)
        #expect(!job.needsExtractionReview)
    }

    @Test func changedPreviewRequiresReviewInsteadOfNewComparison() {
        let job = makeJob(
            status: .awaitingReview,
            repairStatus: .previewReady
        )

        #expect(!job.canRequestSeasonRepair)
        #expect(job.needsSeasonRepairPreview)
        #expect(!job.needsExtractionReview)
    }

    private func makeJob(
        status: SeasonImportJobStatus,
        repairStatus: SeasonRepairStatus
    ) -> SeasonImportJob {
        SeasonImportJob(
            id: "job-1",
            brandID: BrandID(value: "brand-1"),
            jobType: .importSeasonFromURL,
            status: status,
            phase: status == .succeeded ? .completed : .reviewing,
            sourceURL: "https://example.com/lookbook",
            seasonTitle: "SS 2026",
            sourceTitle: nil,
            sourceCandidateID: nil,
            sourceImportJobID: nil,
            targetSeasonID: SeasonID(value: "season-1"),
            requestedBy: "admin-1",
            errorMessage: nil,
            assetRetryStatus: nil,
            assetCompletedCount: 1,
            assetFailedCount: 0,
            reviewStatus: status == .awaitingReview
                ? .repairPreviewReady
                : nil,
            reviewGeneration: 0,
            repairStatus: repairStatus,
            repairGeneration: 1,
            extractionQualityReasons: [],
            createdAt: .distantPast,
            updatedAt: .distantPast
        )
    }
}
