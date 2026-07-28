import Foundation

@MainActor
final class ProfileSetupViewModel {
    struct State {
        var nickname = ""
        var nicknameCountText = "0 / 20"
        var isNextEnabled = false
        var isCheckingNickname = false
        var errorMessage: String?
    }

    private(set) var state = State() {
        didSet { onStateChanged?(state) }
    }

    var onStateChanged: ((State) -> Void)?

    private let checkNicknameAvailabilityUseCase: CheckNicknameAvailabilityUseCase
    private let onNext: (String) -> Void

    init(
        initialNickname: String = "",
        checkNicknameAvailabilityUseCase: CheckNicknameAvailabilityUseCase,
        onNext: @escaping (String) -> Void
    ) {
        self.checkNicknameAvailabilityUseCase = checkNicknameAvailabilityUseCase
        self.onNext = onNext
        setNickname(initialNickname)
    }

    func setNickname(_ text: String) {
        let normalized = text.precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let limited = String(normalized.prefix(20))
        state.nickname = limited
        state.nicknameCountText = "\(limited.count) / 20"
        state.errorMessage = nil
        recompute()
    }

    func nextTapped() {
        Task { await next() }
    }

    func next() async {
        guard state.isNextEnabled, state.isCheckingNickname == false else { return }
        state.isCheckingNickname = true
        state.errorMessage = nil
        recompute()
        do {
            let isAvailable = try await checkNicknameAvailabilityUseCase.execute(
                nickname: state.nickname
            )
            state.isCheckingNickname = false
            if isAvailable {
                onNext(state.nickname)
            } else {
                state.errorMessage = "이미 사용 중인 닉네임이에요"
            }
            recompute()
        } catch {
            state.isCheckingNickname = false
            state.errorMessage = "닉네임을 확인하지 못했어요 잠시 후 다시 시도해 주세요"
            recompute()
        }
    }

    private func recompute() {
        let count = state.nickname.count
        state.isNextEnabled = count >= 2 && count <= 20 && state.isCheckingNickname == false
    }
}
