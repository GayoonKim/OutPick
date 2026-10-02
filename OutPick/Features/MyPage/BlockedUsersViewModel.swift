import Foundation

@MainActor
final class BlockedUsersViewModel {
    struct State: Equatable {
        var users: [UserBlock] = []
        var isLoading = false
        var hasLoaded = false
        var profiles: [String: UserPublicProfile] = [:]
        var unblockingIDs: Set<String> = []
        var errorMessage: String?

        func nickname(for user: UserBlock) -> String {
            let name = profiles[user.blockedUserID.value]?.nickname
                ?? user.blockedUserNicknameSnapshot
            return name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
                ?? "알 수 없는 사용자"
        }
    }

    private(set) var state = State() {
        didSet { onStateChanged?(state) }
    }
    var onStateChanged: ((State) -> Void)?

    private let currentUserID: UserID
    private let repository: any UserBlockRepositoryProtocol
    private let unblockUserUseCase: any UnblockUserUseCaseProtocol
    private let profileRepository: any UserPublicProfileRepositoryProtocol
    private var attemptedProfileIDs: Set<String> = []
    private var profileGeneration = 0

    init(
        currentUserID: String,
        repository: any UserBlockRepositoryProtocol,
        unblockUserUseCase: any UnblockUserUseCaseProtocol,
        profileRepository: any UserPublicProfileRepositoryProtocol
    ) {
        self.currentUserID = UserID(value: currentUserID)
        self.repository = repository
        self.unblockUserUseCase = unblockUserUseCase
        self.profileRepository = profileRepository
    }

    func load() async {
        guard !state.isLoading, state.unblockingIDs.isEmpty else { return }
        state.isLoading = true
        state.errorMessage = nil
        do {
            state.users = try await repository.fetchBlockedUsers(blockerUserID: currentUserID)
            profileGeneration += 1
            attemptedProfileIDs.removeAll()
            let ids = Set(state.users.map { $0.blockedUserID.value })
            state.profiles = state.profiles.filter { ids.contains($0.key) }
            state.hasLoaded = true
            state.isLoading = false
        } catch {
            state.isLoading = false
            state.errorMessage = "차단 목록을 불러오지 못했어요"
        }
    }

    // 화면에 나타난 행만 조회한다. 실패해도 차단 목록과 해제 동작은 유지한다.
    func loadProfile(for user: UserBlock) async {
        let id = user.blockedUserID.value
        guard !state.isLoading,
              state.users.contains(where: { $0.blockedUserID.value == id }),
              attemptedProfileIDs.insert(id).inserted else { return }
        let generation = profileGeneration
        guard let profile = try? await profileRepository.fetchProfile(userID: id),
              generation == profileGeneration,
              state.users.contains(where: { $0.blockedUserID.value == id }) else { return }
        state.profiles[id] = profile
    }

    func unblock(_ user: UserBlock) async {
        let id = user.blockedUserID.value
        guard !state.isLoading,
              state.users.contains(where: { $0.blockedUserID.value == id }),
              !state.unblockingIDs.contains(id) else { return }
        state.unblockingIDs.insert(id)
        state.errorMessage = nil
        defer { state.unblockingIDs.remove(id) }
        do {
            try await unblockUserUseCase.execute(
                blockerUserID: currentUserID,
                blockedUserID: user.blockedUserID
            )
            state.users.removeAll { $0.blockedUserID == user.blockedUserID }
            state.profiles.removeValue(forKey: id)
        } catch {
            state.errorMessage = "차단을 해제하지 못했어요"
        }
    }
}

private extension String {
    var nilIfBlank: String? { isEmpty ? nil : self }
}
