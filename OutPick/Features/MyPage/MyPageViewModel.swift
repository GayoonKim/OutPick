import Foundation

@MainActor
final class MyPageViewModel {
    struct State: Equatable {
        var nickname = ""
        var avatarPath: String?
        var selectedMoodNames: [String] = []
        var isLoading = false
        var errorMessage: String?
    }

    private(set) var state = State() {
        didSet { onStateChanged?(state) }
    }

    var onStateChanged: ((State) -> Void)?
    var onEditProfile: ((UserPublicProfile) -> Void)?
    var onEditStyles: (([String]) -> Void)?
    var onOpenBrandRequests: (() -> Void)?
    var onDeleteAccount: (() -> Void)?

    private let userID: String
    private let accountRepository: CurrentUserAccountRepositoryProtocol
    private let publicProfileRepository: UserPublicProfileRepositoryProtocol
    private let moodRepository: StyleMoodRepositoryProtocol
    private let stylePreferenceStore: CurrentUserStylePreferenceStore
    private var currentProfile: UserPublicProfile?
    private var selectedMoodIDs: [String] = []

    init(
        userID: String,
        accountRepository: CurrentUserAccountRepositoryProtocol,
        publicProfileRepository: UserPublicProfileRepositoryProtocol,
        moodRepository: StyleMoodRepositoryProtocol,
        stylePreferenceStore: CurrentUserStylePreferenceStore,
        initialProfile: UserPublicProfile?
    ) {
        self.userID = userID
        self.accountRepository = accountRepository
        self.publicProfileRepository = publicProfileRepository
        self.moodRepository = moodRepository
        self.stylePreferenceStore = stylePreferenceStore
        currentProfile = initialProfile
        state.nickname = initialProfile?.nickname ?? ""
        state.avatarPath = initialProfile?.avatarThumbPath ?? initialProfile?.avatarOriginalPath
    }

    func load() {
        Task { await loadData() }
    }

    func loadData() async {
        guard state.isLoading == false else { return }
        state.isLoading = true
        state.errorMessage = nil
        do {
            async let profileRequest = publicProfileRepository.fetchProfile(userID: userID)
            async let accountRequest = accountRepository.fetchAccount(userID: userID)
            async let moodsRequest = moodRepository.fetchOnboardingMoods()
            let (profile, account, moods) = try await (
                profileRequest,
                accountRequest,
                moodsRequest
            )
            currentProfile = profile
            selectedMoodIDs = account?.selectedMoodIDs ?? []
            stylePreferenceStore.replace(selectedMoodIDs: selectedMoodIDs)
            let selectedSet = Set(selectedMoodIDs)
            state.nickname = profile.nickname
            state.avatarPath = profile.avatarThumbPath ?? profile.avatarOriginalPath
            state.selectedMoodNames = moods
                .filter { selectedSet.contains($0.id) }
                .map(\.displayName)
            state.isLoading = false
        } catch {
            state.isLoading = false
            state.errorMessage = "내 정보를 불러오지 못했어요"
        }
    }

    func editProfileTapped() {
        guard let currentProfile else { return }
        onEditProfile?(currentProfile)
    }

    func editStylesTapped() {
        onEditStyles?(selectedMoodIDs)
    }

    func brandRequestsTapped() {
        onOpenBrandRequests?()
    }

    func deleteAccountTapped() {
        onDeleteAccount?()
    }

    func apply(profile: UserPublicProfile) {
        currentProfile = profile
        state.nickname = profile.nickname
        state.avatarPath = profile.avatarThumbPath ?? profile.avatarOriginalPath
    }

    func apply(selectedMoodIDs: [String], moods: [StyleMood]) {
        self.selectedMoodIDs = selectedMoodIDs
        let selectedSet = Set(selectedMoodIDs)
        state.selectedMoodNames = moods
            .filter { selectedSet.contains($0.id) }
            .map(\.displayName)
    }
}
