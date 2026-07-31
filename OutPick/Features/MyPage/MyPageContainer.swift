import Foundation

@MainActor
final class MyPageContainer {
    let userID: String
    let accountRepository: CurrentUserAccountRepositoryProtocol
    let publicProfileRepository: UserPublicProfileRepositoryProtocol
    let moodRepository: StyleMoodRepositoryProtocol
    let updatePublicProfileUseCase: UpdatePublicProfileUseCase
    let updateStylePreferencesUseCase: UpdateStylePreferencesUseCase
    let requestAccountDeletionUseCase: RequestAccountDeletionUseCase
    let onAccountDeletionAccepted: (
        AccountDeletionRequestOutcome,
        AuthenticatedUser
    ) -> Void
    let sessionStore: CurrentUserSessionStore
    let stylePreferenceStore: CurrentUserStylePreferenceStore
    let currentUserProvider: CurrentUserProviding
    let avatarImageManager: AvatarImageManaging
    private(set) weak var appContentRouter: (any AppContentRouting)?

    init(
        userID: String,
        accountRepository: CurrentUserAccountRepositoryProtocol,
        publicProfileRepository: UserPublicProfileRepositoryProtocol,
        moodRepository: StyleMoodRepositoryProtocol,
        updatePublicProfileUseCase: UpdatePublicProfileUseCase,
        updateStylePreferencesUseCase: UpdateStylePreferencesUseCase,
        requestAccountDeletionUseCase: RequestAccountDeletionUseCase,
        onAccountDeletionAccepted: @escaping (
            AccountDeletionRequestOutcome,
            AuthenticatedUser
        ) -> Void,
        sessionStore: CurrentUserSessionStore,
        stylePreferenceStore: CurrentUserStylePreferenceStore,
        currentUserProvider: CurrentUserProviding,
        avatarImageManager: AvatarImageManaging
    ) {
        self.userID = userID
        self.accountRepository = accountRepository
        self.publicProfileRepository = publicProfileRepository
        self.moodRepository = moodRepository
        self.updatePublicProfileUseCase = updatePublicProfileUseCase
        self.updateStylePreferencesUseCase = updateStylePreferencesUseCase
        self.requestAccountDeletionUseCase = requestAccountDeletionUseCase
        self.onAccountDeletionAccepted = onAccountDeletionAccepted
        self.sessionStore = sessionStore
        self.stylePreferenceStore = stylePreferenceStore
        self.currentUserProvider = currentUserProvider
        self.avatarImageManager = avatarImageManager
    }

    func configureAppContentRouter(_ appContentRouter: (any AppContentRouting)?) {
        self.appContentRouter = appContentRouter
    }
}
