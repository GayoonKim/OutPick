import Foundation

struct CloudFunctionsSeasonAssetRetryRepository: SeasonAssetRetryRequestingRepository {
    private struct QueueInput: Codable {
        let sourceJobID: String
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

    func requestAssetRetry(
        brandID: BrandID,
        sourceJobID: String
    ) async throws -> SeasonAssetRetryReceipt {
        let prepared = try await requestCoordinator.prepare(
            kind: "assetRetry",
            brandID: brandID.value,
            input: QueueInput(sourceJobID: sourceJobID)
        )
        let sending = try await requestCoordinator.begin(prepared)
        let envelope = requestCoordinator.envelope(for: sending)
        do {
            let response = try await transport.call(
                "requestSeasonAssetRetry",
                data: [
                    "queueContractVersion": envelope.queueContractVersion,
                    "requestID": envelope.requestID,
                    "requestCreatedAt": envelope.requestCreatedAt,
                    "brandID": brandID.value,
                    "sourceJobID": sourceJobID
                ]
            )
            let queueReceipt = try SeasonImportCloudFunctionsMapper.queueReceipt(response)
            try requestCoordinator.validateReceipt(queueReceipt, request: sending, brandID: brandID.value)
            _ = try await requestCoordinator.markAccepted(
                sending,
                brandID: brandID.value,
                batchID: queueReceipt.batchID,
                stateRevision: queueReceipt.stateRevision,
                receipt: queueReceipt
            )
            let item = queueReceipt.items.first
            return SeasonAssetRetryReceipt(
                sourceImportJobID: item?.jobID ?? sourceJobID,
                seasonID: nil,
                status: item?.processingStatus ?? "queued",
                isDuplicate: item?.admissionStatus == "duplicate",
                requestID: queueReceipt.requestID,
                batchID: queueReceipt.batchID
            )
        } catch {
            await requestCoordinator.markNeedsReconcile(sending)
            throw error
        }
    }
}
