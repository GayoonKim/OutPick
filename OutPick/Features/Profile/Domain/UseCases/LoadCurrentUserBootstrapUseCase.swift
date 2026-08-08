import Foundation

enum CurrentUserBootstrapOutcome: Equatable {
    case needsOnboarding
    case ready(account: UserAccount, publicProfile: UserPublicProfile)
    case restricted(
        state: CurrentUserModerationState,
        account: UserAccount?,
        publicProfile: UserPublicProfile?
    )
    case suspended(state: CurrentUserModerationState)
    case deletionPending
}

struct LoadCurrentUserBootstrapUseCase {
    static let currentOnboardingVersion = 1

    private let moderationRepository: CurrentUserModerationRepositoryProtocol
    private let accountRepository: CurrentUserAccountRepositoryProtocol
    private let publicProfileRepository: UserPublicProfileRepositoryProtocol

    init(
        moderationRepository: CurrentUserModerationRepositoryProtocol,
        accountRepository: CurrentUserAccountRepositoryProtocol,
        publicProfileRepository: UserPublicProfileRepositoryProtocol
    ) {
        self.moderationRepository = moderationRepository
        self.accountRepository = accountRepository
        self.publicProfileRepository = publicProfileRepository
    }

    func execute(userID: String) async throws -> CurrentUserBootstrapOutcome {
        let moderationState = try await moderationRepository.fetchAndBindCurrentState()
        if moderationState.status == .suspended {
            return .suspended(state: moderationState)
        }
        guard let account = try await accountRepository.fetchAccount(userID: userID) else {
            if moderationState.status == .restricted {
                return .restricted(
                    state: moderationState,
                    account: nil,
                    publicProfile: nil
                )
            }
            return .needsOnboarding
        }
        if account.accountStatus == .deletionPending {
            return .deletionPending
        }
        guard account.onboardingVersion >= Self.currentOnboardingVersion else {
            if moderationState.status == .restricted {
                return .restricted(
                    state: moderationState,
                    account: account,
                    publicProfile: nil
                )
            }
            return .needsOnboarding
        }
        let publicProfile = try await publicProfileRepository.fetchProfile(userID: userID)
        if moderationState.status == .restricted {
            return .restricted(
                state: moderationState,
                account: account,
                publicProfile: publicProfile
            )
        }
        return .ready(account: account, publicProfile: publicProfile)
    }
}
