import Testing
@testable import OutPick

struct StylePreferenceEditViewModelTests {
    @Test
    @MainActor
    func requiresAtLeastOneMoodAndPersistsChangedSelection() async {
        let mutation = StylePreferenceMutationFake()
        let viewModel = makeViewModel(mutation: mutation)
        await viewModel.loadMoods()

        viewModel.toggleMood(id: "minimal")
        #expect(viewModel.state.isSaveEnabled == false)
        viewModel.toggleMood(id: "street")
        #expect(viewModel.state.isSaveEnabled)
        await viewModel.save()

        #expect(mutation.savedMoodIDs == ["street"])
    }

    @Test
    @MainActor
    func sixthMoodShowsLimitError() async {
        let mutation = StylePreferenceMutationFake()
        let viewModel = StylePreferenceEditViewModel(
            initialMoodIDs: ["1", "2", "3", "4", "5"],
            moodRepository: StylePreferenceMoodRepositoryFake(
                moods: (1...6).map { Self.makeMood(id: "\($0)") }
            ),
            updateUseCase: UpdateStylePreferencesUseCase(mutationRepository: mutation),
            onSaved: { _, _ in }
        )
        await viewModel.loadMoods()
        viewModel.toggleMood(id: "6")

        #expect(viewModel.state.selectedMoodIDs.count == 5)
        #expect(viewModel.state.errorMessage?.contains("최대 5개") == true)
    }

    @Test
    @MainActor
    func loadFailureShowsErrorAndCanBeRetried() async {
        let repository = RetryingStylePreferenceMoodRepositoryFake()
        let viewModel = StylePreferenceEditViewModel(
            initialMoodIDs: ["minimal"],
            moodRepository: repository,
            updateUseCase: UpdateStylePreferencesUseCase(
                mutationRepository: StylePreferenceMutationFake()
            ),
            onSaved: { _, _ in }
        )

        await viewModel.loadMoods()
        #expect(viewModel.state.errorMessage == "관심 스타일을 불러오지 못했어요")

        await viewModel.loadMoods()
        #expect(viewModel.state.moods.map(\.id) == ["minimal", "street"])
        #expect(viewModel.state.errorMessage == nil)
    }

    @Test
    @MainActor
    func saveFailureKeepsSelectionAndAllowsRetry() async {
        let mutation = StylePreferenceMutationFake(updateError: StylePreferenceTestError.failed)
        let viewModel = makeViewModel(mutation: mutation)
        await viewModel.loadMoods()
        viewModel.toggleMood(id: "street")

        await viewModel.save()

        #expect(viewModel.state.selectedMoodIDs == ["minimal", "street"])
        #expect(viewModel.state.errorMessage == "관심 스타일을 저장하지 못했어요")
        #expect(viewModel.state.isSaveEnabled)
    }

    @Test
    @MainActor
    func repeatedSaveWhileMutationIsInFlightCallsMutationOnce() async throws {
        let mutation = StylePreferenceMutationFake(updateDelayNanoseconds: 150_000_000)
        let viewModel = makeViewModel(mutation: mutation)
        await viewModel.loadMoods()
        viewModel.toggleMood(id: "street")

        viewModel.saveTapped()
        viewModel.saveTapped()
        try await Task.sleep(nanoseconds: 250_000_000)

        #expect(mutation.updateCallCount == 1)
    }

    @MainActor
    private func makeViewModel(
        mutation: StylePreferenceMutationFake
    ) -> StylePreferenceEditViewModel {
        StylePreferenceEditViewModel(
            initialMoodIDs: ["minimal"],
            moodRepository: StylePreferenceMoodRepositoryFake(moods: [
                Self.makeMood(id: "minimal"),
                Self.makeMood(id: "street")
            ]),
            updateUseCase: UpdateStylePreferencesUseCase(mutationRepository: mutation),
            onSaved: { _, _ in }
        )
    }

    private static func makeMood(id: String) -> StyleMood {
        StyleMood(
            id: id,
            displayName: id,
            displayGroup: .essential,
            sortOrder: 0,
            isFeaturedInOnboarding: true
        )
    }
}

private final class StylePreferenceMoodRepositoryFake: StyleMoodRepositoryProtocol {
    let moods: [StyleMood]
    init(moods: [StyleMood]) { self.moods = moods }
    func fetchOnboardingMoods() async throws -> [StyleMood] { moods }
}

private final class StylePreferenceMutationFake: ProfileMutationRepositoryProtocol {
    var savedMoodIDs: [String] = []
    let updateError: Error?
    let updateDelayNanoseconds: UInt64
    var updateCallCount = 0

    init(
        updateError: Error? = nil,
        updateDelayNanoseconds: UInt64 = 0
    ) {
        self.updateError = updateError
        self.updateDelayNanoseconds = updateDelayNanoseconds
    }

    func checkNicknameAvailability(nickname: String) async throws -> Bool { true }
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
        updateCallCount += 1
        if updateDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: updateDelayNanoseconds)
        }
        if let updateError { throw updateError }
        savedMoodIDs = selectedMoodIDs
    }
}

private final class RetryingStylePreferenceMoodRepositoryFake: StyleMoodRepositoryProtocol {
    private var callCount = 0

    func fetchOnboardingMoods() async throws -> [StyleMood] {
        callCount += 1
        if callCount == 1 {
            throw StylePreferenceTestError.failed
        }
        return [
            StyleMood(
                id: "minimal",
                displayName: "minimal",
                displayGroup: .essential,
                sortOrder: 0,
                isFeaturedInOnboarding: true
            ),
            StyleMood(
                id: "street",
                displayName: "street",
                displayGroup: .essential,
                sortOrder: 1,
                isFeaturedInOnboarding: true
            )
        ]
    }
}

private enum StylePreferenceTestError: Error {
    case failed
}
