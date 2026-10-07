import CryptoKit
import Foundation

struct LookbookImportQueueRequestCoordinator {
    private let requestStore: any LookbookImportRequestStoringRepositoryProtocol
    private let ownerUIDProvider: () -> String
    private let now: () -> Date

    init(
        requestStore: any LookbookImportRequestStoringRepositoryProtocol,
        ownerUIDProvider: @escaping () -> String,
        now: @escaping () -> Date = Date.init
    ) {
        self.requestStore = requestStore
        self.ownerUIDProvider = ownerUIDProvider
        self.now = now
    }

    func prepare<Input: Encodable>(
        kind: String,
        brandID: String?,
        input: Input
    ) async throws -> LookbookImportRequest {
        let ownerUID = ownerUIDProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ownerUID.isEmpty else {
            throw NSError(
                domain: "LookbookImportQueueRequestCoordinator",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "로그인 정보를 확인할 수 없습니다. 다시 로그인해 주세요."]
            )
        }
        let payload = try Self.encoder().encode(input)
        let envelope = LookbookImportQueueContract.makeRequestEnvelope(now: now())
        let timestamp = Self.timestamp(now())
        let proposed = LookbookImportRequest(
            ownerUID: ownerUID,
            requestID: envelope.requestID,
            contractVersion: envelope.queueContractVersion,
            brandID: brandID,
            kind: kind,
            inputJSON: String(decoding: payload, as: UTF8.self),
            payloadDigest: Self.digest(payload),
            localState: .prepared,
            batchID: nil,
            receiptJSON: nil,
            stateRevision: nil,
            createdAt: envelope.requestCreatedAt,
            updatedAt: timestamp,
            settledAt: nil,
            expiresAt: nil
        )
        return try await requestStore.prepareOrReuse(proposed).request
    }

    func begin(_ request: LookbookImportRequest) async throws -> LookbookImportRequest {
        var updated = request
        updated.localState = .submitting
        updated.updatedAt = timestamp()
        try await requestStore.update(updated)
        return updated
    }

    func markAccepted<Receipt: Encodable>(
        _ request: LookbookImportRequest,
        brandID: String?,
        batchID: String?,
        stateRevision: Int64?,
        receipt: Receipt,
        isSettled: Bool = false
    ) async throws -> LookbookImportRequest {
        var updated = request
        updated.brandID = brandID ?? updated.brandID
        updated.batchID = batchID
        updated.stateRevision = stateRevision
        updated.receiptJSON = String(decoding: try Self.encoder().encode(receipt), as: UTF8.self)
        updated.updatedAt = timestamp()
        if isSettled {
            updated.localState = .settled
            updated.settledAt = updated.updatedAt
            updated.expiresAt = updated.updatedAt
                + (LookbookImportQueueContract.policy["localSettledRetentionMs"] ?? 2_592_000_000)
        } else {
            updated.localState = .accepted
            updated.settledAt = nil
            updated.expiresAt = nil
        }
        try await requestStore.update(updated)
        return updated
    }

    func markNeedsReconcile(_ request: LookbookImportRequest) async {
        var updated = request
        guard updated.localState != .settled else { return }
        updated.localState = .needsReconcile
        updated.updatedAt = timestamp()
        try? await requestStore.update(updated)
    }

    func envelope(for request: LookbookImportRequest) -> LookbookImportQueueContract.RequestEnvelope {
        LookbookImportQueueContract.RequestEnvelope(
            queueContractVersion: request.contractVersion,
            requestID: request.requestID,
            requestCreatedAt: request.createdAt
        )
    }

    func validateReceipt(
        _ receipt: LookbookImportQueueReceipt,
        request: LookbookImportRequest,
        brandID: String
    ) throws {
        guard LookbookImportQueueContract.receiptMatches(
            receipt,
            request: envelope(for: request),
            brandID: brandID,
            kind: request.kind
        ) else {
            throw CloudFunctionsClientError.invalidResponse
        }
    }

    private func timestamp() -> Int64 {
        Self.timestamp(now())
    }

    private static func timestamp(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded(.down))
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
