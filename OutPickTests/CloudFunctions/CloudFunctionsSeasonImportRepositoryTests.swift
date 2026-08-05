import Foundation
import Testing
@testable import OutPick

struct CloudFunctionsSeasonImportRepositoryTests {
    @Test func coversSeasonImportCallableContracts() async throws {
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [
            ["jobID": "job-1", "status": "queued", "seasonURL": "https://season.example.com"],
            [
                "brandID": "brand-1", "candidateIDs": ["candidate-1"], "jobIDs": ["job-2"],
                "requestedJobCount": 1, "failedJobCount": 0, "skippedJobCount": 0
            ],
            ["sourceImportJobID": "job-1", "seasonID": "season-1", "status": "queued"],
            [
                "brandID": "brand-1", "jobID": "discovery-1", "generation": 3,
                "status": "queued", "coalesced": true,
                "sourceArchiveURL": "https://archive.example.com"
            ]
        ]
        let brandID = BrandID(value: "brand-1")
        let importing = CloudFunctionsSeasonImportRepository(transport: transport)
        let jobs = CloudFunctionsSeasonImportJobRequestingRepository(transport: transport)
        let retry = CloudFunctionsSeasonAssetRetryRepository(transport: transport)
        let discovery = CloudFunctionsSeasonCandidateDiscoveryRepository(
            transport: transport,
            observeJob: { _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield([
                        "status": "succeeded",
                        "candidateCount": 4,
                        "candidateSnapshotHash": "snapshot-hash"
                    ])
                    continuation.finish()
                }
            }
        )

        _ = try await importing.requestSeasonImport(
            brandID: brandID,
            seasonURL: "https://season.example.com",
            sourceCandidateID: nil
        )
        let batch = try await jobs.requestSeasonCandidateImportJobs(
            brandID: brandID,
            discoveryJobID: "discovery-1",
            generation: 3,
            candidateIDs: ["candidate-1"],
            candidateSnapshotHash: "snapshot-hash"
        )
        _ = try await retry.requestAssetRetry(brandID: brandID, sourceJobID: "job-1")
        let result = try await discovery.discoverSeasonCandidates(brandID: brandID)

        #expect(transport.calls.map(\.name) == [
            "requestSeasonImport", "requestSeasonCandidateImportJobs",
            "requestSeasonAssetRetry", "requestSeasonDiscovery"
        ])
        #expect(transport.calls[0].data["sourceCandidateID"] == nil)
        #expect(transport.calls[3].data["requestReason"] as? String == "manualRefresh")
        #expect(batch.requestedImportJobCount == 1)
        #expect(result.candidateCount == 4)
    }

    @Test func coversExtractionReviewCallableContracts() async throws {
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [
            [
                "jobID": "job-1",
                "brandID": "brand-1",
                "status": "awaitingReview",
                "reviewStatus": "pending",
                "reviewGeneration": 1,
                "reviewSnapshotHash": "snapshot",
                "qualityReasons": ["programmatic_gallery_requires_review"],
                "expectedCountEvidence": [["value": 2]],
                "extractionIssueStatus": "fixed",
                "retryAvailableRuntimeVersion": "extractor:1.3.0",
                "canRetryAfterFix": true,
                "candidates": [
                    [
                        "candidateKey": "candidate-1",
                        "sourceURL": "https://example.com/1.jpg"
                    ]
                ]
            ],
            ["status": "queued", "duplicate": false],
            ["status": "queued", "duplicate": false]
        ]
        let repository = CloudFunctionsLookbookExtractionReviewRepository(
            transport: transport
        )
        let brandID = BrandID(value: "brand-1")
        let review = try await repository.loadReview(
            brandID: brandID,
            jobID: "job-1"
        )
        _ = try await repository.submitReview(
            brandID: brandID,
            review: review,
            decision: .approved,
            excludedCandidateKeys: [],
            expectedCandidateCount: nil,
            note: nil
        )
        _ = try await repository.retryAfterExtractionFix(
            brandID: brandID,
            jobID: "job-1"
        )

        #expect(transport.calls.map(\.name) == [
            "getLookbookExtractionReview",
            "reviewLookbookExtraction",
            "retryLookbookExtractionAfterFix"
        ])
        #expect(review.candidates.map(\.candidateKey) == ["candidate-1"])
        #expect(transport.calls[1].data["reviewGeneration"] as? Int == 1)
    }

    @Test func coversSeasonRepairCallableContracts() async throws {
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [
            [
                "jobID": "job-1", "seasonID": "season-1",
                "repairGeneration": 2, "status": "analyzing", "duplicate": false
            ],
            [
                "jobID": "job-1", "brandID": "brand-1", "seasonID": "season-1",
                "repairGeneration": 2, "repairSnapshotHash": "repair-hash",
                "status": "previewReady", "resultingPostCount": 3,
                "keep": [
                    [
                        "postID": "post-1", "sourceURL": "https://example.com/1.jpg",
                        "previousIndex": 0, "proposedIndex": 0, "matchedBy": "canonicalURL"
                    ]
                ],
                "add": [
                    [
                        "postID": "repair-2", "candidateKey": "candidate-2",
                        "sourceURL": "https://example.com/2.jpg",
                        "proposedIndex": 1, "contentHash": NSNull(), "alt": NSNull()
                    ]
                ],
                "reorder": [],
                "removeCandidates": [
                    [
                        "postID": "post-3", "sourceURL": "https://example.com/3.jpg",
                        "previousIndex": 2, "proposedIndex": 2
                    ]
                ]
            ],
            [
                "jobID": "job-1", "seasonID": "season-1",
                "repairGeneration": 2, "status": "applied", "duplicate": false
            ]
        ]
        let repository = CloudFunctionsLookbookSeasonRepairRepository(
            transport: transport
        )
        let brandID = BrandID(value: "brand-1")
        let seasonID = SeasonID(value: "season-1")

        _ = try await repository.requestRepair(
            brandID: brandID,
            seasonID: seasonID,
            sourceImportJobID: "job-1"
        )
        let preview = try await repository.loadPreview(
            brandID: brandID,
            jobID: "job-1"
        )
        _ = try await repository.applyRepair(
            brandID: brandID,
            preview: preview
        )

        #expect(transport.calls.map(\.name) == [
            "requestLookbookSeasonRepair",
            "previewLookbookSeasonRepair",
            "applyLookbookSeasonRepair"
        ])
        #expect(preview.keep.map(\.postID) == ["post-1"])
        #expect(preview.add.map(\.postID) == ["repair-2"])
        #expect(preview.removeCandidates.map(\.postID) == ["post-3"])
        #expect(
            transport.calls[2].data["repairSnapshotHash"] as? String
                == "repair-hash"
        )
    }
}
