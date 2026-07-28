import Foundation
import Testing
@testable import OutPick

struct LoadCurrentUserBootstrapUseCaseTests {
    @Test
    func missingAccountRequiresOnboardingWithoutReadingPublicProfile() async throws {
        let accountRepository = CurrentUserAccountRepositoryFake(account: nil)
        let publicRepository = UserPublicProfileRepositoryFake()
        let useCase = LoadCurrentUserBootstrapUseCase(
            accountRepository: accountRepository,
            publicProfileRepository: publicRepository
        )

        let outcome = try await useCase.execute(userID: "user-1")

        #expect(outcome == .needsOnboarding)
        #expect(publicRepository.requestedUserIDs.isEmpty)
    }

    @Test
    func outdatedOnboardingVersionRequiresOnboarding() async throws {
        let account = makeAccount(onboardingVersion: 0)
        let useCase = LoadCurrentUserBootstrapUseCase(
            accountRepository: CurrentUserAccountRepositoryFake(account: account),
            publicProfileRepository: UserPublicProfileRepositoryFake()
        )

        #expect(try await useCase.execute(userID: "user-1") == .needsOnboarding)
    }

    @Test
    func deletionPendingAccountBlocksMainFlow() async throws {
        let account = makeAccount(accountStatus: .deletionPending)
        let useCase = LoadCurrentUserBootstrapUseCase(
            accountRepository: CurrentUserAccountRepositoryFake(account: account),
            publicProfileRepository: UserPublicProfileRepositoryFake()
        )

        #expect(try await useCase.execute(userID: "user-1") == .deletionPending)
    }

    @Test
    func completedAccountLoadsPublicProfile() async throws {
        let account = makeAccount()
        let profile = UserPublicProfile(
            userID: "user-1",
            nickname: "아웃피커",
            avatarThumbPath: "profileImages/user-1/thumb/a.jpg",
            avatarOriginalPath: "profileImages/user-1/original/a.jpg",
            createdAt: nil,
            updatedAt: nil
        )
        let useCase = LoadCurrentUserBootstrapUseCase(
            accountRepository: CurrentUserAccountRepositoryFake(account: account),
            publicProfileRepository: UserPublicProfileRepositoryFake(profile: profile)
        )

        #expect(
            try await useCase.execute(userID: "user-1")
                == .ready(account: account, publicProfile: profile)
        )
    }

    private func makeAccount(
        onboardingVersion: Int = LoadCurrentUserBootstrapUseCase.currentOnboardingVersion,
        accountStatus: UserAccountStatus = .active
    ) -> UserAccount {
        UserAccount(
            userID: "user-1",
            onboardingVersion: onboardingVersion,
            selectedMoodIDs: ["minimal"],
            accountStatus: accountStatus,
            onboardingCompletedAt: nil,
            createdAt: nil,
            updatedAt: nil
        )
    }
}

private final class CurrentUserAccountRepositoryFake: CurrentUserAccountRepositoryProtocol {
    let account: UserAccount?

    init(account: UserAccount?) {
        self.account = account
    }

    func fetchAccount(userID: String) async throws -> UserAccount? {
        account
    }
}

private final class UserPublicProfileRepositoryFake: UserPublicProfileRepositoryProtocol {
    let profile: UserPublicProfile?
    private(set) var requestedUserIDs: [String] = []

    init(profile: UserPublicProfile? = nil) {
        self.profile = profile
    }

    func fetchProfile(userID: String) async throws -> UserPublicProfile {
        requestedUserIDs.append(userID)
        guard let profile else {
            throw FirebaseError.FailedToFetchProfile
        }
        return profile
    }

    func fetchProfiles(userIDs: [String]) async throws -> [String: UserPublicProfile] {
        [:]
    }
}
