import Foundation

struct CloudFunctionsLookbookExtractionReviewRepository:
    LookbookExtractionReviewRepositoryProtocol {
    private struct ReviewQueueInput: Codable {
        let jobID: String
        let reviewGeneration: Int
        let reviewSnapshotHash: String
        let decision: String
        let excludedCandidateKeys: [String]
        let expectedCandidateCount: Int?
        let note: String?
    }

    private struct RetryQueueInput: Codable {
        let jobID: String
    }

    private let transport: any CloudFunctionsTransporting
    private let requestCoordinator: LookbookImportQueueRequestCoordinator

    init(
        transport: any CloudFunctionsTransporting = FirebaseCloudFunctionsTransport(),
        requestStore: any LookbookImportRequestStoringRepositoryProtocol = UnavailableLookbookImportRequestStore(),
        currentUserUIDProvider: @escaping () -> String = { LoginManagerCurrentUserProvider().canonicalUserID }
    ) {
        self.transport = transport
        requestCoordinator = LookbookImportQueueRequestCoordinator(
            requestStore: requestStore,
            ownerUIDProvider: currentUserUIDProvider
        )
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
        let normalizedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let queueBacked = decision != .insufficientImages
        var request: LookbookImportRequest?
        if queueBacked {
            let prepared = try await requestCoordinator.prepare(
                kind: "reviewApproval",
                brandID: brandID.value,
                input: ReviewQueueInput(
                    jobID: review.jobID,
                    reviewGeneration: review.reviewGeneration,
                    reviewSnapshotHash: review.reviewSnapshotHash,
                    decision: decision.rawValue,
                    excludedCandidateKeys: excludedCandidateKeys,
                    expectedCandidateCount: expectedCandidateCount,
                    note: normalizedNote?.isEmpty == false ? normalizedNote : nil
                )
            )
            request = try await requestCoordinator.begin(prepared)
        }
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
        if let normalizedNote, !normalizedNote.isEmpty {
            data["note"] = normalizedNote
        }
        do {
            if let request {
                data.merge(requestFields(for: request)) { _, new in new }
            }
            let response = try await transport.call("reviewLookbookExtraction", data: data)
            guard let request else {
                return try LookbookExtractionReviewCloudFunctionsMapper.receipt(response)
            }
            let queueReceipt = try SeasonImportCloudFunctionsMapper.queueReceipt(response)
            try requestCoordinator.validateReceipt(queueReceipt, request: request, brandID: brandID.value)
            _ = try await requestCoordinator.markAccepted(
                request,
                brandID: brandID.value,
                batchID: queueReceipt.batchID,
                stateRevision: queueReceipt.stateRevision,
                receipt: queueReceipt
            )
            return LookbookExtractionReviewReceipt(
                status: "queued",
                duplicate: queueReceipt.items.first?.admissionStatus == "duplicate",
                requestID: queueReceipt.requestID,
                batchID: queueReceipt.batchID
            )
        } catch {
            if let request { await requestCoordinator.markNeedsReconcile(request) }
            throw error
        }
    }

    func retryAfterExtractionFix(
        brandID: BrandID,
        jobID: String
    ) async throws -> LookbookExtractionReviewReceipt {
        let prepared = try await requestCoordinator.prepare(
            kind: "manualRetry",
            brandID: brandID.value,
            input: RetryQueueInput(jobID: jobID)
        )
        let request = try await requestCoordinator.begin(prepared)
        var data = requestFields(for: request)
        data["brandID"] = brandID.value
        data["jobID"] = jobID
        do {
            let response = try await transport.call("retryLookbookExtractionAfterFix", data: data)
            let receipt = try SeasonImportCloudFunctionsMapper.queueReceipt(response)
            try requestCoordinator.validateReceipt(receipt, request: request, brandID: brandID.value)
            _ = try await requestCoordinator.markAccepted(
                request,
                brandID: brandID.value,
                batchID: receipt.batchID,
                stateRevision: receipt.stateRevision,
                receipt: receipt
            )
            return LookbookExtractionReviewReceipt(
                status: "queued",
                duplicate: receipt.items.first?.admissionStatus == "duplicate",
                requestID: receipt.requestID,
                batchID: receipt.batchID
            )
        } catch {
            await requestCoordinator.markNeedsReconcile(request)
            throw error
        }
    }

    private func requestFields(for request: LookbookImportRequest) -> [String: Any] {
        let envelope = requestCoordinator.envelope(for: request)
        return [
            "queueContractVersion": envelope.queueContractVersion,
            "requestID": envelope.requestID,
            "requestCreatedAt": envelope.requestCreatedAt
        ]
    }
}
