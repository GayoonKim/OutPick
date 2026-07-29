import UIKit

protocol AccountDeletionReauthenticating {
    @MainActor
    func reauthenticateForAccountDeletion(
        expectedUser: AuthenticatedUser,
        presenter: UIViewController
    ) async throws

    @MainActor
    func authenticatePendingAccount(
        provider: AuthProvider,
        presenter: UIViewController
    ) async throws -> AuthenticatedUser
}
