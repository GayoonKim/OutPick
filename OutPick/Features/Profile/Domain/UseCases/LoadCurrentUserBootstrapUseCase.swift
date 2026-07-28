import Foundation

enum CurrentUserBootstrapOutcome: Equatable {
    case needsOnboarding
    case ready(account: UserAccount, publicProfile: UserPublicProfile)
    case deletionPending
}

struct LoadCurrentUserBootstrapUseCase {
    static let currentOnboardingVersion = 1

    private let accountRepository: CurrentUserAccountRepositoryProtocol
    private let publicProfileRepository: UserPublicProfileRepositoryProtocol

    init(
        accountRepository: CurrentUserAccountRepositoryProtocol,
        publicProfileRepository: UserPublicProfileRepositoryProtocol
    ) {
        self.accountRepository = accountRepository
        self.publicProfileRepository = publicProfileRepository
    }

    func execute(userID: String) async throws -> CurrentUserBootstrapOutcome {
        guard let account = try await accountRepository.fetchAccount(userID: userID) else {
            return .needsOnboarding
        }
        if account.accountStatus == .deletionPending {
            return .deletionPending
        }
        guard account.onboardingVersion >= Self.currentOnboardingVersion else {
            return .needsOnboarding
        }
        let publicProfile = try await publicProfileRepository.fetchProfile(userID: userID)
        return .ready(account: account, publicProfile: publicProfile)
    }
}
