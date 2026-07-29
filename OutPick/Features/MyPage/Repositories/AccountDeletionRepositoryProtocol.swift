import Foundation

protocol AccountDeletionRepositoryProtocol {
    func prepareDeletion() async throws -> AccountDeletionIntent
    func requestDeletion(intent: AccountDeletionIntent) async throws -> AccountDeletionReceiptPayload
    func cancelDeletion() async throws -> AccountDeletionCancellation
    func loadStatus(receipt: AccountDeletionReceipt) async throws -> AccountDeletionStatusSnapshot
}

struct AccountDeletionReceiptPayload: Equatable, Sendable {
    let requestID: String
    let receiptToken: String
    let requestedAt: Date
    let cancelableUntil: Date
}
