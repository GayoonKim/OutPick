import Foundation

struct CloudFunctionsLookbookSeasonRepairRepository:
    LookbookSeasonRepairRepositoryProtocol {
    private struct AnalyzeQueueInput: Codable {
        let seasonID: String
        let sourceImportJobID: String
    }

    private struct ApplyQueueInput: Codable {
        let jobID: String
        let repairGeneration: Int
        let repairSnapshotHash: String
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

    func requestRepair(
        brandID: BrandID,
        seasonID: SeasonID,
        sourceImportJobID: String
    ) async throws -> LookbookSeasonRepairReceipt {
        let prepared = try await requestCoordinator.prepare(
            kind: "repair",
            brandID: brandID.value,
            input: AnalyzeQueueInput(seasonID: seasonID.value, sourceImportJobID: sourceImportJobID)
        )
        let request = try await requestCoordinator.begin(prepared)
        var data = requestFields(for: request)
        data["brandID"] = brandID.value
        data["seasonID"] = seasonID.value
        data["sourceImportJobID"] = sourceImportJobID
        do {
            let response = try await transport.call("requestLookbookSeasonRepair", data: data)
            let receipt = try SeasonImportCloudFunctionsMapper.queueReceipt(response)
            try requestCoordinator.validateReceipt(receipt, request: request, brandID: brandID.value)
            _ = try await requestCoordinator.markAccepted(
                request,
                brandID: brandID.value,
                batchID: receipt.batchID,
                stateRevision: receipt.stateRevision,
                receipt: receipt
            )
            let item = receipt.items.first
            return LookbookSeasonRepairReceipt(
                jobID: item?.jobID ?? sourceImportJobID,
                seasonID: seasonID,
                generation: 0,
                status: .analyzing,
                duplicate: item?.admissionStatus == "duplicate",
                requestID: receipt.requestID,
                batchID: receipt.batchID
            )
        } catch {
            await requestCoordinator.markNeedsReconcile(request)
            throw error
        }
    }

    func loadPreview(
        brandID: BrandID,
        jobID: String
    ) async throws -> LookbookSeasonRepairPreview {
        let response = try await transport.call(
            "previewLookbookSeasonRepair",
            data: ["brandID": brandID.value, "jobID": jobID]
        )
        return try LookbookSeasonRepairCloudFunctionsMapper.preview(response)
    }

    func applyRepair(
        brandID: BrandID,
        preview: LookbookSeasonRepairPreview
    ) async throws -> LookbookSeasonRepairReceipt {
        let prepared = try await requestCoordinator.prepare(
            kind: "repair",
            brandID: brandID.value,
            input: ApplyQueueInput(
                jobID: preview.jobID,
                repairGeneration: preview.generation,
                repairSnapshotHash: preview.snapshotHash
            )
        )
        let request = try await requestCoordinator.begin(prepared)
        var data = requestFields(for: request)
        data["brandID"] = brandID.value
        data["jobID"] = preview.jobID
        data["repairGeneration"] = preview.generation
        data["repairSnapshotHash"] = preview.snapshotHash
        do {
            let response = try await transport.call("applyLookbookSeasonRepair", data: data)
            let receipt = try SeasonImportCloudFunctionsMapper.queueReceipt(response)
            try requestCoordinator.validateReceipt(receipt, request: request, brandID: brandID.value)
            _ = try await requestCoordinator.markAccepted(
                request,
                brandID: brandID.value,
                batchID: receipt.batchID,
                stateRevision: receipt.stateRevision,
                receipt: receipt
            )
            let item = receipt.items.first
            return LookbookSeasonRepairReceipt(
                jobID: item?.jobID ?? preview.jobID,
                seasonID: preview.seasonID,
                generation: preview.generation,
                status: .applying,
                duplicate: item?.admissionStatus == "duplicate",
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
