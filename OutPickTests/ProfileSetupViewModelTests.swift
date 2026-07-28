import Testing
@testable import OutPick

@MainActor
struct ProfileSetupViewModelTests {
    @Test
    func nicknameRequiresTwoToTwentyNormalizedCharacters() async {
        var receivedNickname: String?
        let repository = ProfileSetupMutationRepositoryStub(isNicknameAvailable: true)
        let viewModel = makeViewModel(
            repository: repository,
            onNext: { receivedNickname = $0 }
        )

        viewModel.setNickname(" 가 ")

        #expect(viewModel.state.nickname == "가")
        #expect(viewModel.state.isNextEnabled == false)

        viewModel.setNickname("  아웃피커  ")
        await viewModel.next()

        #expect(viewModel.state.nickname == "아웃피커")
        #expect(viewModel.state.nicknameCountText == "4 / 20")
        #expect(viewModel.state.isNextEnabled)
        #expect(receivedNickname == "아웃피커")
        #expect(repository.checkedNicknames == ["아웃피커"])
    }

    @Test
    func nicknameIsLimitedToTwentyCharacters() {
        let viewModel = makeViewModel()

        viewModel.setNickname(String(repeating: "가", count: 21))

        #expect(viewModel.state.nickname.count == 20)
        #expect(viewModel.state.nicknameCountText == "20 / 20")
        #expect(viewModel.state.isNextEnabled)
    }

    @Test
    func unavailableNicknameStaysOnNicknameStepAndErrorClearsWhenChanged() async {
        var didMoveNext = false
        let viewModel = makeViewModel(
            repository: ProfileSetupMutationRepositoryStub(isNicknameAvailable: false),
            onNext: { _ in didMoveNext = true }
        )
        viewModel.setNickname("아웃피커")

        await viewModel.next()

        #expect(viewModel.state.errorMessage == "이미 사용 중인 닉네임이에요")
        #expect(didMoveNext == false)

        viewModel.setNickname("새아웃피커")
        #expect(viewModel.state.errorMessage == nil)
    }

    @Test
    func nicknameCheckFailureStaysOnNicknameStepWithRetryMessage() async {
        var didMoveNext = false
        let viewModel = makeViewModel(
            repository: ProfileSetupMutationRepositoryStub(error: ProfileSetupTestError.failed),
            onNext: { _ in didMoveNext = true }
        )
        viewModel.setNickname("아웃피커")

        await viewModel.next()

        #expect(
            viewModel.state.errorMessage
                == "닉네임을 확인하지 못했어요 잠시 후 다시 시도해 주세요"
        )
        #expect(viewModel.state.isNextEnabled)
        #expect(didMoveNext == false)
    }

    private func makeViewModel(
        repository: ProfileSetupMutationRepositoryStub = ProfileSetupMutationRepositoryStub(
            isNicknameAvailable: true
        ),
        onNext: @escaping (String) -> Void = { _ in }
    ) -> ProfileSetupViewModel {
        ProfileSetupViewModel(
            checkNicknameAvailabilityUseCase: CheckNicknameAvailabilityUseCase(
                mutationRepository: repository
            ),
            onNext: onNext
        )
    }
}

private enum ProfileSetupTestError: Error {
    case failed
}

private final class ProfileSetupMutationRepositoryStub: ProfileMutationRepositoryProtocol {
    let isNicknameAvailable: Bool
    let error: Error?
    private(set) var checkedNicknames: [String] = []

    init(isNicknameAvailable: Bool = false, error: Error? = nil) {
        self.isNicknameAvailable = isNicknameAvailable
        self.error = error
    }

    func checkNicknameAvailability(nickname: String) async throws -> Bool {
        checkedNicknames.append(nickname)
        if let error { throw error }
        return isNicknameAvailable
    }

    func completeOnboarding(
        nickname: String,
        selectedMoodIDs: [String]
    ) async throws -> CompleteOnboardingMutationResult {
        fatalError("사용하지 않음")
    }

    func updatePublicProfile(
        nickname: String?,
        avatarMutation: ProfileAvatarPathMutation
    ) async throws -> UserPublicProfile {
        fatalError("사용하지 않음")
    }

    func updateStylePreferences(selectedMoodIDs: [String]) async throws {
        fatalError("사용하지 않음")
    }
}
