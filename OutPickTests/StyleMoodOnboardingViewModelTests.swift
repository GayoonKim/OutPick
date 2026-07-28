import Testing
@testable import OutPick

@MainActor
struct StyleMoodOnboardingViewModelTests {
    @Test
    func selectingOneMoodEnablesCompletionAndSixthSelectionIsRejected() async {
        let moods = (1...6).map {
            StyleMood(
                id: "mood-\($0)",
                displayName: "무드 \($0)",
                displayGroup: .essential,
                sortOrder: $0,
                isFeaturedInOnboarding: true
            )
        }
        let viewModel = makeViewModel(moods: moods)
        await viewModel.loadMoods()

        viewModel.toggleMood(id: "mood-1")
        #expect(viewModel.state.isCompleteEnabled)
        #expect(viewModel.state.selectionText == "1 / 5")

        for id in 2...6 {
            viewModel.toggleMood(id: "mood-\(id)")
        }

        #expect(viewModel.state.selectedMoodIDs.count == 5)
        #expect(viewModel.state.selectedMoodIDs.contains("mood-6") == false)
        #expect(viewModel.state.errorMessage == "관심 무드는 최대 5개까지 선택할 수 있어요")
    }

    @Test
    func completionPreservesServerSortOrderForSelectedMoodIDs() async {
        let moods = [
            StyleMood(id: "minimal", displayName: "미니멀", displayGroup: .essential, sortOrder: 1, isFeaturedInOnboarding: true),
            StyleMood(id: "street", displayName: "스트릿", displayGroup: .street, sortOrder: 2, isFeaturedInOnboarding: true)
        ]
        let mutation = ProfileMutationRepositoryFake()
        var completedOutcome: CompleteOnboardingOutcome?
        let viewModel = makeViewModel(
            moods: moods,
            mutationRepository: mutation,
            onCompleted: { completedOutcome = $0 }
        )
        await viewModel.loadMoods()

        viewModel.toggleMood(id: "street")
        viewModel.toggleMood(id: "minimal")
        await viewModel.complete()

        #expect(mutation.completedMoodIDs == ["minimal", "street"])
        #expect(completedOutcome?.publicProfile.nickname == "아웃피커")
    }

    @Test
    func defaultShowsFeaturedAndSearchFiltersAllActiveMoods() async {
        let moods = [
            StyleMood(id: "minimal", displayName: "미니멀", displayGroup: .essential, sortOrder: 1, isFeaturedInOnboarding: true),
            StyleMood(id: "avant_garde", displayName: "아방가르드", displayGroup: .romantic, sortOrder: 2, isFeaturedInOnboarding: false)
        ]
        let viewModel = makeViewModel(moods: moods)
        await viewModel.loadMoods()

        #expect(viewModel.state.visibleMoods.map(\.id) == ["minimal"])

        viewModel.setSearchQuery("아방")

        #expect(viewModel.state.visibleMoods.map(\.id) == ["avant_garde"])
        #expect(viewModel.state.emptyMessage == nil)
    }

    @Test
    func selectionIsPreservedWhenSearchResultChanges() async {
        let moods = [
            StyleMood(id: "minimal", displayName: "미니멀", displayGroup: .essential, sortOrder: 1, isFeaturedInOnboarding: true),
            StyleMood(id: "street", displayName: "스트릿", displayGroup: .street, sortOrder: 2, isFeaturedInOnboarding: true)
        ]
        let viewModel = makeViewModel(moods: moods)
        await viewModel.loadMoods()
        viewModel.toggleMood(id: "minimal")

        viewModel.setSearchQuery("스트릿")

        #expect(viewModel.state.visibleMoods.map(\.id) == ["street"])
        #expect(viewModel.state.selectedMoodIDs == ["minimal"])
        #expect(viewModel.state.isCompleteEnabled)
    }

    private func makeViewModel(
        moods: [StyleMood],
        mutationRepository: ProfileMutationRepositoryFake = ProfileMutationRepositoryFake(),
        onCompleted: @escaping (CompleteOnboardingOutcome) -> Void = { _ in }
    ) -> StyleMoodOnboardingViewModel {
        StyleMoodOnboardingViewModel(
            userID: "user-1",
            draft: OnboardingDraft(nickname: "아웃피커", avatar: nil),
            moodRepository: StyleMoodRepositoryFake(moods: moods),
            completeOnboardingUseCase: CompleteOnboardingUseCase(
                mutationRepository: mutationRepository,
                avatarUploader: ProfileAvatarUploaderFake()
            ),
            onBack: {},
            onCompleted: onCompleted
        )
    }
}

private final class StyleMoodRepositoryFake: StyleMoodRepositoryProtocol {
    let moods: [StyleMood]

    init(moods: [StyleMood]) {
        self.moods = moods
    }

    func fetchOnboardingMoods() async throws -> [StyleMood] {
        moods
    }
}
