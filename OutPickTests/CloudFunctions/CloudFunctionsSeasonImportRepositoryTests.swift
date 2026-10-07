import Foundation
import Testing
@testable import OutPick

struct CloudFunctionsSeasonImportRepositoryTests {
    @Test func rejectsReceiptWithDifferentRequestIDAndKeepsRecordUnresolved() async throws {
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [[:]]
        transport.responseHandler = { call in
            guard call.name == "requestSeasonImport" else { return nil }
            var response = Self.queueReceipt(
                call,
                kind: "importSeasons",
                targetID: "season-url",
                jobID: "job-1"
            )
            response["requestID"] = "223e4567-e89b-42d3-a456-426614174000"
            return response
        }
        let requestStore = GRDBLookbookImportRequestStore(database: try TemporaryAppDatabase.make())
        let repository = CloudFunctionsSeasonImportRepository(
            transport: transport,
            requestStore: requestStore,
            currentUserUIDProvider: { "user-1" }
        )

        do {
            _ = try await repository.requestSeasonImport(
                brandID: BrandID(value: "brand-1"),
                seasonURL: "https://season.example.com",
                sourceCandidateID: nil
            )
            Issue.record("다른 요청의 영수증을 받아들이면 안 됩니다.")
        } catch {
            #expect(transport.calls.count == 1)
        }
        let unresolved = try await requestStore.fetchUnsettled(ownerUID: "user-1", brandID: "brand-1")
        #expect(unresolved.count == 1)
        #expect(unresolved[0].localState == .needsReconcile)
    }

    @Test func coversSeasonImportCallableContracts() async throws {
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [
            [:], [:], [:], [:]
        ]
        let brandID = BrandID(value: "brand-1")
        let requestStore = GRDBLookbookImportRequestStore(database: try TemporaryAppDatabase.make())
        transport.responseHandler = { call in
            switch call.name {
            case "requestSeasonImport":
                return Self.queueReceipt(call, kind: "importSeasons", targetID: "season-url", jobID: "job-1")
            case "requestSeasonCandidateImportJobs":
                return Self.queueReceipt(call, kind: "importSeasons", targetID: "candidate-1", jobID: "job-1")
            case "requestSeasonAssetRetry":
                return Self.queueReceipt(call, kind: "assetRetry", targetID: "job-1", jobID: "job-1")
            case "requestSeasonDiscovery":
                return Self.queueReceipt(call, kind: "discoverSeasons", targetID: "brand-1", jobID: "discovery-1")
            default:
                return nil
            }
        }
        let importing = CloudFunctionsSeasonImportRepository(
            transport: transport,
            requestStore: requestStore,
            currentUserUIDProvider: { "user-1" }
        )
        let jobs = CloudFunctionsSeasonImportJobRequestingRepository(transport: transport)
        let retry = CloudFunctionsSeasonAssetRetryRepository(
            transport: transport,
            requestStore: requestStore,
            currentUserUIDProvider: { "user-1" }
        )
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
            },
            requestStore: requestStore,
            currentUserUIDProvider: { "user-1" },
            sourceArchiveURLProvider: { _ in "https://archive.example.com" }
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
            candidateSnapshotHash: "snapshot-hash",
            envelope: LookbookImportQueueContract.RequestEnvelope(
                queueContractVersion: 1,
                requestID: "123e4567-e89b-42d3-a456-426614174000",
                requestCreatedAt: 1_800_000_000_000
            )
        )
        _ = try await retry.requestAssetRetry(brandID: brandID, sourceJobID: "job-1")
        let result = try await discovery.discoverSeasonCandidates(brandID: brandID)

        #expect(transport.calls.map(\.name) == [
            "requestSeasonImport", "requestSeasonCandidateImportJobs",
            "requestSeasonAssetRetry", "requestSeasonDiscovery"
        ])
        #expect(transport.calls[0].data["sourceCandidateID"] == nil)
        #expect(transport.calls[3].data["requestReason"] as? String == "manualRefresh")
        #expect(batch.items.map(\.targetID) == ["candidate-1"])
        #expect(transport.calls[1].data["requestID"] as? String == "123e4567-e89b-42d3-a456-426614174000")
        #expect(transport.calls[1].data["queueContractVersion"] as? Int == 1)
        #expect(result.candidateCount == 4)
        for index in [0, 2, 3] {
            #expect(transport.calls[index].data["queueContractVersion"] as? Int == 1)
            #expect(transport.calls[index].data["requestID"] as? String != nil)
            #expect(transport.calls[index].data["requestCreatedAt"] as? Int64 != nil)
        }
        let acceptedRequests = try await requestStore.fetchUnsettled(ownerUID: "user-1", brandID: brandID.value)
        #expect(acceptedRequests.count == 3)
        #expect(acceptedRequests.allSatisfy { $0.localState == .accepted })
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
            [:], [:]
        ]
        transport.responseHandler = { call in
            guard ["reviewLookbookExtraction", "retryLookbookExtractionAfterFix"].contains(call.name) else {
                return nil
            }
            return Self.queueReceipt(
                call,
                kind: call.name == "reviewLookbookExtraction" ? "reviewApproval" : "manualRetry",
                targetID: "job-1",
                jobID: "job-1"
            )
        }
        let requestStore = GRDBLookbookImportRequestStore(database: try TemporaryAppDatabase.make())
        let repository = CloudFunctionsLookbookExtractionReviewRepository(
            transport: transport,
            requestStore: requestStore,
            currentUserUIDProvider: { "user-1" }
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
        #expect(transport.calls[1].data["requestID"] as? String != nil)
        #expect(transport.calls[2].data["requestID"] as? String != nil)
    }

    @Test func coversSeasonRepairCallableContracts() async throws {
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [
            [:],
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
            [:]
        ]
        transport.responseHandler = { call in
            guard ["requestLookbookSeasonRepair", "applyLookbookSeasonRepair"].contains(call.name) else {
                return nil
            }
            return Self.queueReceipt(
                call,
                kind: "repair",
                targetID: "season-1",
                jobID: "job-1"
            )
        }
        let requestStore = GRDBLookbookImportRequestStore(database: try TemporaryAppDatabase.make())
        let repository = CloudFunctionsLookbookSeasonRepairRepository(
            transport: transport,
            requestStore: requestStore,
            currentUserUIDProvider: { "user-1" }
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
        #expect(transport.calls[0].data["requestID"] as? String != nil)
        #expect(transport.calls[2].data["requestID"] as? String != nil)
    }

    private static func queueReceipt(
        _ call: CloudFunctionsTransportSpy.Call,
        kind: String,
        targetID: String,
        jobID: String
    ) -> [String: Any] {
        [
            "contractVersion": 1,
            "requestID": call.data["requestID"] as? String ?? "123e4567-e89b-42d3-a456-426614174000",
            "batchID": String(repeating: "a", count: 64),
            "brandID": call.data["brandID"] as? String ?? "brand-1",
            "kind": kind,
            "receiptState": "queued",
            "stateRevision": 1,
            "items": [[
                "itemID": "item-1",
                "targetID": targetID,
                "ordinal": 0,
                "admissionStatus": "created",
                "processingStatus": "queued",
                "jobID": jobID,
                "executionID": "execution-1",
                "errorCode": NSNull()
            ]]
        ]
    }
}
