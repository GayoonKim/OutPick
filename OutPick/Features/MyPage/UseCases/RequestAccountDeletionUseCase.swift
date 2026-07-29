import UIKit

struct AccountDeletionRequestOutcome: Equatable {
    let receipt: AccountDeletionReceipt
    let receiptPersisted: Bool
    let localCleanupCompleted: Bool
}

@MainActor
final class RequestAccountDeletionUseCase {
    private let repository: AccountDeletionRepositoryProtocol
    private let reauthenticator: AccountDeletionReauthenticating
    private let receiptStore: AccountDeletionReceiptStoring
    private let localDataScrubber: AccountDeletionLocalDataScrubbing

    init(
        repository: AccountDeletionRepositoryProtocol,
        reauthenticator: AccountDeletionReauthenticating,
        receiptStore: AccountDeletionReceiptStoring,
        localDataScrubber: AccountDeletionLocalDataScrubbing
    ) {
        self.repository = repository
        self.reauthenticator = reauthenticator
        self.receiptStore = receiptStore
        self.localDataScrubber = localDataScrubber
    }

    func execute(
        expectedUser: AuthenticatedUser,
        presenter: UIViewController
    ) async throws -> AccountDeletionRequestOutcome {
        try await reauthenticator.reauthenticateForAccountDeletion(
            expectedUser: expectedUser,
            presenter: presenter
        )
        let intent = try await repository.prepareDeletion()
        let payload = try await repository.requestDeletion(intent: intent)
        let receipt = AccountDeletionReceipt(
            requestID: payload.requestID,
            receiptToken: payload.receiptToken,
            requestedAt: payload.requestedAt,
            cancelableUntil: payload.cancelableUntil,
            provider: expectedUser.provider
        )

        let receiptPersisted: Bool
        do {
            try receiptStore.save(receipt)
            receiptPersisted = true
        } catch {
            receiptPersisted = false
        }

        let localCleanupCompleted: Bool
        do {
            try await localDataScrubber.scrub()
            localCleanupCompleted = true
        } catch {
            localCleanupCompleted = false
        }
        return AccountDeletionRequestOutcome(
            receipt: receipt,
            receiptPersisted: receiptPersisted,
            localCleanupCompleted: localCleanupCompleted
        )
    }
}
