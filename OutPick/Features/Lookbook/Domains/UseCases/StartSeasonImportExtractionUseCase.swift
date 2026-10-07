import CryptoKit
import Foundation

protocol StartSeasonImportExtractionUseCaseProtocol {
    func execute(
        brandID: BrandID,
        candidates: [SeasonCandidate]
    ) async throws -> LookbookImportQueueReceipt

    func loadProgress(requestID: String) async throws -> SeasonImportExtractionProgress

    func reconcileUnsettledRequests(brandID: BrandID) async throws -> [LookbookImportQueueReceipt]

    func latestUnsettledRequestID(brandID: BrandID) async throws -> String?

    func unsettledRequestID(
        brandID: BrandID,
        candidates: [SeasonCandidate]
    ) async throws -> String?
}

final class StartSeasonImportExtractionUseCase: StartSeasonImportExtractionUseCaseProtocol {
    private struct CandidateImportInput: Codable, Equatable {
        let brandID: String
        let discoveryJobID: String
        let generation: Int
        let candidateIDs: [String]
        let candidateSnapshotHash: String
    }

    private let importJobRequestingRepository: any SeasonImportJobRequestingRepositoryProtocol
    private let requestStore: any LookbookImportRequestStoringRepositoryProtocol
    private let ownerUIDProvider: () -> String
    private let now: () -> Date

    init(
        importJobRequestingRepository: any SeasonImportJobRequestingRepositoryProtocol,
        requestStore: any LookbookImportRequestStoringRepositoryProtocol,
        ownerUIDProvider: @escaping () -> String,
        now: @escaping () -> Date = Date.init
    ) {
        self.importJobRequestingRepository = importJobRequestingRepository
        self.requestStore = requestStore
        self.ownerUIDProvider = ownerUIDProvider
        self.now = now
    }

    func execute(
        brandID: BrandID,
        candidates: [SeasonCandidate]
    ) async throws -> LookbookImportQueueReceipt {
        guard let first = candidates.first,
              candidates.allSatisfy({
                  $0.discoveryJobID == first.discoveryJobID &&
                  $0.discoveryGeneration == first.discoveryGeneration &&
                  $0.candidateSnapshotHash == first.candidateSnapshotHash &&
                  $0.resolution == "newSeason"
              }) else {
            throw NSError(
                domain: "StartSeasonImportExtractionUseCase",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "현재 공개된 신규 시즌 후보만 선택할 수 있습니다."]
            )
        }
        let input = CandidateImportInput(
            brandID: brandID.value,
            discoveryJobID: first.discoveryJobID,
            generation: first.discoveryGeneration,
            candidateIDs: candidates.map(\.id),
            candidateSnapshotHash: first.candidateSnapshotHash
        )
        return try await submitOrRestore(input)
    }

    func loadProgress(requestID: String) async throws -> SeasonImportExtractionProgress {
        let receipt = try await importJobRequestingRepository.getSeasonImportBatch(requestID: requestID)
        try validate(receipt, requestID: requestID, brandID: receipt.brandID, kind: "importSeasons")
        try await updateStoredReceipt(receipt)
        return Self.progress(from: receipt)
    }

    func reconcileUnsettledRequests(brandID: BrandID) async throws -> [LookbookImportQueueReceipt] {
        let ownerUID = try currentOwnerUID()
        let requests = try await requestStore.fetchUnsettled(
            ownerUID: ownerUID,
            brandID: brandID.value
        )
        var receipts: [LookbookImportQueueReceipt] = []
        for request in requests {
            if request.kind != "importSeasons" {
                do {
                    let receipt = try await importJobRequestingRepository.getSeasonImportBatch(
                        requestID: request.requestID
                    )
                    try validate(
                        receipt,
                        requestID: request.requestID,
                        brandID: brandID.value,
                        kind: request.kind
                    )
                    try await updateStoredReceipt(receipt)
                    receipts.append(receipt)
                } catch {
                    // 이미 접수한 다른 API 종류는 상태 조회만 시도한다.
                }
                continue
            }
            guard request.kind == "importSeasons",
                  let inputData = request.inputJSON.data(using: .utf8),
                  let input = try? JSONDecoder().decode(CandidateImportInput.self, from: inputData) else {
                continue
            }
            do {
                receipts.append(try await reconcileOrSubmit(request: request, input: input))
            } catch {
                // 실패한 조회 기록은 계속 남겨 두고 다른 미확정 요청도 복원한다.
            }
        }
        return receipts
    }

    func latestUnsettledRequestID(brandID: BrandID) async throws -> String? {
        let requests = try await requestStore.fetchUnsettled(
            ownerUID: currentOwnerUID(),
            brandID: brandID.value
        )
        return requests.first(where: { $0.kind == "importSeasons" })?.requestID
    }

    func unsettledRequestID(
        brandID: BrandID,
        candidates: [SeasonCandidate]
    ) async throws -> String? {
        guard let first = candidates.first else { return nil }
        let input = CandidateImportInput(
            brandID: brandID.value,
            discoveryJobID: first.discoveryJobID,
            generation: first.discoveryGeneration,
            candidateIDs: candidates.map(\.id),
            candidateSnapshotHash: first.candidateSnapshotHash
        )
        let digest = Self.digest(try Self.encoder().encode(input))
        let requests = try await requestStore.fetchUnsettled(
            ownerUID: currentOwnerUID(),
            brandID: brandID.value
        )
        return requests.first(where: {
            $0.kind == "importSeasons" && $0.payloadDigest == digest
        })?.requestID
    }

    private func submitOrRestore(_ input: CandidateImportInput) async throws -> LookbookImportQueueReceipt {
        let ownerUID = try currentOwnerUID()
        let payloadData = try Self.encoder().encode(input)
        let inputJSON = String(decoding: payloadData, as: UTF8.self)
        let digest = Self.digest(payloadData)
        let envelope = LookbookImportQueueContract.makeRequestEnvelope(now: now())
        let proposed = LookbookImportRequest(
            ownerUID: ownerUID,
            requestID: envelope.requestID,
            contractVersion: envelope.queueContractVersion,
            brandID: input.brandID,
            kind: "importSeasons",
            inputJSON: inputJSON,
            payloadDigest: digest,
            localState: .prepared,
            batchID: nil,
            receiptJSON: nil,
            stateRevision: nil,
            createdAt: envelope.requestCreatedAt,
            updatedAt: envelope.requestCreatedAt,
            settledAt: nil,
            expiresAt: nil
        )
        let prepared = try await requestStore.prepareOrReuse(proposed)
        if prepared.didReuse && prepared.request.localState != .prepared {
            do {
                let receipt = try await importJobRequestingRepository.getSeasonImportBatch(
                    requestID: prepared.request.requestID
                )
                try validate(
                    receipt,
                    requestID: prepared.request.requestID,
                    brandID: input.brandID,
                    kind: prepared.request.kind
                )
                try await updateStoredReceipt(receipt)
                return receipt
            } catch {
                // 같은 ID의 접수 재전송은 서버 멱등성으로 응답 유실을 복구한다.
            }
        }
        return try await send(prepared.request, input: input)
    }

    private func reconcileOrSubmit(
        request: LookbookImportRequest,
        input: CandidateImportInput
    ) async throws -> LookbookImportQueueReceipt {
        do {
            let receipt = try await importJobRequestingRepository.getSeasonImportBatch(
                requestID: request.requestID
            )
            try validate(
                receipt,
                requestID: request.requestID,
                brandID: input.brandID,
                kind: request.kind
            )
            try await updateStoredReceipt(receipt)
            return receipt
        } catch {
            return try await send(request, input: input)
        }
    }

    private func send(
        _ savedRequest: LookbookImportRequest,
        input: CandidateImportInput
    ) async throws -> LookbookImportQueueReceipt {
        var request = savedRequest
        request.localState = .submitting
        request.updatedAt = timestamp()
        try await requestStore.update(request)
        let envelope = LookbookImportQueueContract.RequestEnvelope(
            queueContractVersion: request.contractVersion,
            requestID: request.requestID,
            requestCreatedAt: request.createdAt
        )
        do {
            let receipt = try await importJobRequestingRepository.requestSeasonCandidateImportJobs(
                brandID: BrandID(value: input.brandID),
                discoveryJobID: input.discoveryJobID,
                generation: input.generation,
                candidateIDs: input.candidateIDs,
                candidateSnapshotHash: input.candidateSnapshotHash,
                envelope: envelope
            )
            try validate(
                receipt,
                requestID: envelope.requestID,
                brandID: input.brandID,
                kind: request.kind
            )
            try await updateStoredReceipt(receipt)
            return receipt
        } catch {
            request.localState = .needsReconcile
            request.updatedAt = timestamp()
            try? await requestStore.update(request)
            throw error
        }
    }

    private func updateStoredReceipt(_ receipt: LookbookImportQueueReceipt) async throws {
        let ownerUID = try currentOwnerUID()
        let requests = try await requestStore.fetchUnsettled(ownerUID: ownerUID, brandID: receipt.brandID)
        guard var request = requests.first(where: { $0.requestID == receipt.requestID }) else { return }
        if let currentRevision = request.stateRevision,
           currentRevision > receipt.stateRevision {
            return
        }
        let data = try Self.encoder().encode(receipt)
        request.batchID = receipt.batchID
        request.receiptJSON = String(decoding: data, as: UTF8.self)
        request.stateRevision = receipt.stateRevision
        request.updatedAt = timestamp()
        if receipt.isSettled {
            request.localState = .settled
            request.settledAt = request.updatedAt
            request.expiresAt = request.updatedAt + 2_592_000_000
        } else {
            request.localState = .accepted
        }
        try await requestStore.update(request)
    }

    private func currentOwnerUID() throws -> String {
        let ownerUID = ownerUIDProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ownerUID.isEmpty else {
            throw NSError(
                domain: "StartSeasonImportExtractionUseCase",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "로그인 정보를 확인할 수 없습니다. 다시 로그인해 주세요."]
            )
        }
        return ownerUID
    }

    private func validate(
        _ receipt: LookbookImportQueueReceipt,
        requestID: String,
        brandID: String,
        kind: String
    ) throws {
        guard receipt.contractVersion == LookbookImportQueueContract.version,
              receipt.requestID == requestID,
              receipt.brandID == brandID,
              receipt.kind == kind else {
            throw CloudFunctionsClientError.invalidResponse
        }
    }

    private func timestamp() -> Int64 {
        Int64((now().timeIntervalSince1970 * 1_000).rounded(.down))
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func progress(from receipt: LookbookImportQueueReceipt) -> SeasonImportExtractionProgress {
        let items = receipt.items.map { item in
            SeasonImportExtractionProgress.Item(
                candidateID: item.targetID,
                jobID: item.jobID,
                status: itemStatus(admissionStatus: item.admissionStatus, processingStatus: item.processingStatus)
            )
        }
        let terminalCount = items.filter { $0.status.isTerminal }.count
        let failedCount = items.filter { $0.status == .failed || $0.status == .skipped }.count
        return SeasonImportExtractionProgress(
            totalCount: items.count,
            matchedJobCount: receipt.items.filter { $0.jobID != nil }.count,
            completedCount: terminalCount,
            failedCount: failedCount,
            items: items,
            batchState: receipt.state,
            stateRevision: receipt.stateRevision
        )
    }

    private static func itemStatus(admissionStatus: String, processingStatus: String?) -> SeasonImportExtractionProgress.ItemStatus {
        if admissionStatus == "failed" { return .failed }
        if admissionStatus == "skipped" { return .skipped }
        if admissionStatus == "pending" { return .queued }
        guard let processingStatus else {
            return admissionStatus == "duplicate" ? .duplicate : .queued
        }
        switch processingStatus {
        case "queued", "dispatching": return .queued
        case "active", "processing", "draining", "running": return .processing
        case "retryWaiting": return .retryWaiting
        case "awaitingReview": return .awaitingReview
        case "succeeded", "completed": return .succeeded
        case "partialFailed", "failed", "cancelled": return .failed
        case "recoveryRequired": return .recoveryRequired
        default: return .recoveryRequired
        }
    }
}
