import Foundation

@MainActor
final class MyPageContainer {
    let userID: String
    let accountRepository: CurrentUserAccountRepositoryProtocol
    let publicProfileRepository: UserPublicProfileRepositoryProtocol
    let moodRepository: StyleMoodRepositoryProtocol
    let updatePublicProfileUseCase: UpdatePublicProfileUseCase
    let updateStylePreferencesUseCase: UpdateStylePreferencesUseCase
    let sessionStore: CurrentUserSessionStore
    let currentUserProvider: CurrentUserProviding
    let avatarImageManager: AvatarImageManaging

    init(
        userID: String,
        accountRepository: CurrentUserAccountRepositoryProtocol,
        publicProfileRepository: UserPublicProfileRepositoryProtocol,
        moodRepository: StyleMoodRepositoryProtocol,
        updatePublicProfileUseCase: UpdatePublicProfileUseCase,
        updateStylePreferencesUseCase: UpdateStylePreferencesUseCase,
        sessionStore: CurrentUserSessionStore,
        currentUserProvider: CurrentUserProviding,
        avatarImageManager: AvatarImageManaging
    ) {
        self.userID = userID
        self.accountRepository = accountRepository
        self.publicProfileRepository = publicProfileRepository
        self.moodRepository = moodRepository
        self.updatePublicProfileUseCase = updatePublicProfileUseCase
        self.updateStylePreferencesUseCase = updateStylePreferencesUseCase
        self.sessionStore = sessionStore
        self.currentUserProvider = currentUserProvider
        self.avatarImageManager = avatarImageManager
    }
}
