import Foundation

@MainActor
final class BlockedUsersViewModel {
    struct State: Equatable {
        var users: [UserBlock] = []
        var isLoading = false
        var errorMessage: String?
    }

    private(set) var state = State() {
        didSet { onStateChanged?(state) }
    }
    var onStateChanged: ((State) -> Void)?

    private let currentUserID: UserID
    private let repository: any UserBlockRepositoryProtocol
    private let unblockUserUseCase: any UnblockUserUseCaseProtocol

    init(
        currentUserID: String,
        repository: any UserBlockRepositoryProtocol,
        unblockUserUseCase: any UnblockUserUseCaseProtocol
    ) {
        self.currentUserID = UserID(value: currentUserID)
        self.repository = repository
        self.unblockUserUseCase = unblockUserUseCase
    }

    func load() async {
        guard !state.isLoading else { return }
        state.isLoading = true
        state.errorMessage = nil
        do {
            state.users = try await repository.fetchBlockedUsers(blockerUserID: currentUserID)
            state.isLoading = false
        } catch {
            state.isLoading = false
            state.errorMessage = "차단 목록을 불러오지 못했어요"
        }
    }

    func unblock(_ user: UserBlock) async {
        do {
            try await unblockUserUseCase.execute(
                blockerUserID: currentUserID,
                blockedUserID: user.blockedUserID
            )
            state.users.removeAll { $0.blockedUserID == user.blockedUserID }
        } catch {
            state.errorMessage = "차단을 해제하지 못했어요"
        }
    }
}
