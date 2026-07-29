import UIKit

struct AccountDeletionCancelOutcome {
    let authenticatedUser: AuthenticatedUser
    let cancellation: AccountDeletionCancellation
    let receiptRemoved: Bool
}

@MainActor
final class CancelAccountDeletionUseCase {
    private let repository: AccountDeletionRepositoryProtocol
    private let reauthenticator: AccountDeletionReauthenticating
    private let receiptStore: AccountDeletionReceiptStoring

    init(
        repository: AccountDeletionRepositoryProtocol,
        reauthenticator: AccountDeletionReauthenticating,
        receiptStore: AccountDeletionReceiptStoring
    ) {
        self.repository = repository
        self.reauthenticator = reauthenticator
        self.receiptStore = receiptStore
    }

    func execute(
        provider: AuthProvider,
        expectedUser: AuthenticatedUser?,
        presenter: UIViewController
    ) async throws -> AccountDeletionCancelOutcome {
        let authenticatedUser: AuthenticatedUser
        if let expectedUser {
            guard expectedUser.provider == provider else {
                throw AccountDeletionClientError.providerMismatch
            }
            try await reauthenticator.reauthenticateForAccountDeletion(
                expectedUser: expectedUser,
                presenter: presenter
            )
            authenticatedUser = expectedUser
        } else {
            authenticatedUser = try await reauthenticator.authenticatePendingAccount(
                provider: provider,
                presenter: presenter
            )
        }

        let cancellation = try await repository.cancelDeletion()
        let receiptRemoved: Bool
        do {
            try receiptStore.delete()
            receiptRemoved = true
        } catch {
            receiptRemoved = false
        }
        return AccountDeletionCancelOutcome(
            authenticatedUser: authenticatedUser,
            cancellation: cancellation,
            receiptRemoved: receiptRemoved
        )
    }
}
