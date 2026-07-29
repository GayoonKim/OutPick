import Foundation

final class LoadAccountDeletionStatusUseCase {
    private let repository: AccountDeletionRepositoryProtocol
    private let receiptStore: AccountDeletionReceiptStoring

    init(
        repository: AccountDeletionRepositoryProtocol,
        receiptStore: AccountDeletionReceiptStoring
    ) {
        self.repository = repository
        self.receiptStore = receiptStore
    }

    func storedReceipt() throws -> AccountDeletionReceipt? {
        try receiptStore.load()
    }

    func execute(
        receipt: AccountDeletionReceipt
    ) async throws -> AccountDeletionStatusSnapshot {
        try await repository.loadStatus(receipt: receipt)
    }

    func removeReceipt() throws {
        try receiptStore.delete()
    }
}
