//
//  CloudFunctionsSeasonImportRepository.swift
//  OutPick
//
//  Created by Codex on 4/23/26.
//

import Foundation

/// Cloud Functions를 통해 시즌 URL import job을 생성하는 구현입니다.
struct CloudFunctionsSeasonImportRepository: SeasonImportRequestingRepository {
    private struct QueueInput: Codable {
        let brandID: String
        let seasonURL: String
        let sourceCandidateID: String?
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

    func requestSeasonImport(
        brandID: BrandID,
        seasonURL: String,
        sourceCandidateID: String?
    ) async throws -> SeasonImportRequestReceipt {
        let prepared = try await requestCoordinator.prepare(
            kind: "importSeasons",
            brandID: brandID.value,
            input: QueueInput(brandID: brandID.value, seasonURL: seasonURL, sourceCandidateID: sourceCandidateID)
        )
        let sending = try await requestCoordinator.begin(prepared)
        var data = requestFields(for: sending)
        data["brandID"] = brandID.value
        data["seasonURL"] = seasonURL
        if let sourceCandidateID { data["sourceCandidateID"] = sourceCandidateID }
        do {
            let response = try await transport.call("requestSeasonImport", data: data)
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
            return SeasonImportRequestReceipt(
                jobID: item?.jobID ?? (item.map {
                    LookbookImportQueueContract.deterministicJobID(batchID: queueReceipt.batchID, itemID: $0.itemID)
                } ?? queueReceipt.batchID),
                status: item?.processingStatus ?? "queued",
                normalizedSeasonURL: seasonURL,
                sourceCandidateID: sourceCandidateID,
                isDuplicate: item?.admissionStatus == "duplicate",
                requestID: queueReceipt.requestID,
                batchID: queueReceipt.batchID
            )
        } catch {
            await requestCoordinator.markNeedsReconcile(sending)
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
