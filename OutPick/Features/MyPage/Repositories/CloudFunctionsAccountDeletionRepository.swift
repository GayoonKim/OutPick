import Foundation

final class CloudFunctionsAccountDeletionRepository: AccountDeletionRepositoryProtocol {
    private let transport: CloudFunctionsTransporting

    init(transport: CloudFunctionsTransporting) {
        self.transport = transport
    }

    func prepareDeletion() async throws -> AccountDeletionIntent {
        let response = try await transport.call("prepareAccountDeletion", data: [:])
        let decoder = CloudFunctionResponseDecoder(dictionary: response)
        return AccountDeletionIntent(
            intentID: try decoder.string("intentID"),
            nonce: try decoder.string("nonce"),
            expiresAt: try requiredDate(decoder, key: "expiresAt")
        )
    }

    func requestDeletion(
        intent: AccountDeletionIntent
    ) async throws -> AccountDeletionReceiptPayload {
        let response = try await transport.call(
            "requestAccountDeletion",
            data: [
                "intentID": intent.intentID,
                "nonce": intent.nonce
            ]
        )
        let decoder = CloudFunctionResponseDecoder(dictionary: response)
        guard try decoder.string("accountStatus") == "deletionPending" else {
            throw AccountDeletionClientError.invalidResponse
        }
        return AccountDeletionReceiptPayload(
            requestID: try decoder.string("requestID"),
            receiptToken: try decoder.string("receiptToken"),
            requestedAt: try requiredDate(decoder, key: "requestedAt"),
            cancelableUntil: try requiredDate(decoder, key: "cancelableUntil")
        )
    }

    func cancelDeletion() async throws -> AccountDeletionCancellation {
        let response = try await transport.call("cancelAccountDeletion", data: [:])
        let decoder = CloudFunctionResponseDecoder(dictionary: response)
        guard try decoder.string("accountStatus") == "active" else {
            throw AccountDeletionClientError.invalidResponse
        }
        return AccountDeletionCancellation(
            requestID: try decoder.string("requestID"),
            cancelledAt: try requiredDate(decoder, key: "cancelledAt")
        )
    }

    func loadStatus(
        receipt: AccountDeletionReceipt
    ) async throws -> AccountDeletionStatusSnapshot {
        let response = try await transport.call(
            "getAccountDeletionStatus",
            data: [
                "requestID": receipt.requestID,
                "receiptToken": receipt.receiptToken
            ]
        )
        let decoder = CloudFunctionResponseDecoder(dictionary: response)
        guard let status = AccountDeletionStatus(rawValue: try decoder.string("status")) else {
            throw AccountDeletionClientError.invalidResponse
        }
        return AccountDeletionStatusSnapshot(
            status: status,
            requestedAt: optionalDate(decoder, key: "requestedAt"),
            cancelableUntil: optionalDate(decoder, key: "cancelableUntil"),
            completedAt: optionalDate(decoder, key: "completedAt"),
            message: try decoder.string("message")
        )
    }

    private func requiredDate(
        _ decoder: CloudFunctionResponseDecoder,
        key: String
    ) throws -> Date {
        guard let value = AccountDeletionISO8601.date(from: try decoder.string(key)) else {
            throw AccountDeletionClientError.invalidResponse
        }
        return value
    }

    private func optionalDate(
        _ decoder: CloudFunctionResponseDecoder,
        key: String
    ) -> Date? {
        guard let value = decoder.optionalString(key) else { return nil }
        return AccountDeletionISO8601.date(from: value)
    }
}
