import Testing
@testable import OutPick

@MainActor
struct StyleMoodManagementViewModelTests {
    @Test
    func canonicalKoreanDisplayGroupsMapWithoutFallingBackToOther() {
        #expect(StyleMoodGroup(rawValueOrOther: "베이직·포멀") == .essential)
        #expect(StyleMoodGroup(rawValueOrOther: "스포츠·아웃도어") == .sports)
        #expect(StyleMoodGroup(rawValueOrOther: "미래 그룹") == .other)
    }

    @Test
    func createdMoodIsReloadedAndReturnedForImmediateSelection() async {
        let moodRepository = StyleMoodRepositoryStub()
        let adminRepository = StyleMoodAdminRepositoryStub()
        let viewModel = StyleMoodManagementViewModel(
            moodRepository: moodRepository,
            adminRepository: adminRepository
        )
        let draft = StyleMoodMutationDraft(
            moodID: nil,
            displayName: "뉴 무드",
            displayGroup: .street,
            aliases: [],
            sortOrder: nil,
            isFeaturedInOnboarding: false
        )

        let saved = await viewModel.save(
            existingMood: nil,
            draft: draft,
            status: .active
        )

        #expect(adminRepository.createdDrafts == [draft])
        #expect(saved?.id == "new_mood")
        #expect(viewModel.moods.map(\.id) == ["new_mood"])
    }

    @Test
    func styleKeywordSearchMatchesNameAndAliasesAndHidesOtherGroups() async {
        let moodRepository = StyleMoodRepositoryStub(
            moods: [
                StyleMood(
                    id: "minimal",
                    displayName: "미니멀",
                    displayGroup: .essential,
                    aliases: ["Minimal"],
                    sortOrder: 10,
                    isFeaturedInOnboarding: true
                ),
                StyleMood(
                    id: "streetwear",
                    displayName: "스트릿",
                    displayGroup: .street,
                    aliases: ["Streetwear", "Urban"],
                    sortOrder: 20,
                    isFeaturedInOnboarding: true
                )
            ]
        )
        let viewModel = StyleMoodManagementViewModel(
            moodRepository: moodRepository,
            adminRepository: StyleMoodAdminRepositoryStub()
        )
        await viewModel.load()

        viewModel.searchText = "  URBAN  "

        #expect(viewModel.visibleMoods(in: .street).map(\.id) == ["streetwear"])
        #expect(viewModel.visibleMoods(in: .essential).isEmpty)

        viewModel.searchText = "미니"

        #expect(viewModel.visibleMoods(in: .essential).map(\.id) == ["minimal"])
    }

    @Test
    func brandStylePickerRequiresQueryAndOnlyReturnsActiveNameOrAliasMatches() {
        let moods = [
            StyleMood(
                id: "dark_academia",
                displayName: "다크 아카데미아",
                displayGroup: .vintage,
                aliases: ["Dark Academia"],
                sortOrder: 10,
                isFeaturedInOnboarding: false
            ),
            StyleMood(
                id: "inactive_dark",
                displayName: "다크 로맨틱",
                displayGroup: .romantic,
                aliases: ["Dark Romantic"],
                sortOrder: 20,
                isFeaturedInOnboarding: false,
                status: .inactive
            )
        ]

        #expect(StyleMoodPickerPolicy.searchResults(in: moods, query: "").isEmpty)
        #expect(StyleMoodPickerPolicy.searchResults(in: moods, query: "  ").isEmpty)
        #expect(
            StyleMoodPickerPolicy.searchResults(in: moods, query: "DARK").map(\.id) ==
            ["dark_academia"]
        )
        #expect(
            StyleMoodPickerPolicy.searchResults(in: moods, query: "아카데미아").map(\.id) ==
            ["dark_academia"]
        )
    }

    @Test
    func brandStylePickerOnlyOffersCreateForNonemptyUnmatchedQueryBelowLimit() {
        let matchingMood = StyleMood(
            id: "dark_academia",
            displayName: "다크 아카데미아",
            displayGroup: .vintage,
            aliases: ["Dark Academia"],
            sortOrder: 10,
            isFeaturedInOnboarding: false
        )

        #expect(
            StyleMoodPickerPolicy.shouldShowCreateAction(
                query: "새 스타일",
                matchingMoods: [],
                selectedCount: 4,
                maximumSelectionCount: 5
            )
        )
        #expect(
            StyleMoodPickerPolicy.shouldShowCreateAction(
                query: "",
                matchingMoods: [],
                selectedCount: 0,
                maximumSelectionCount: 5
            ) == false
        )
        #expect(
            StyleMoodPickerPolicy.shouldShowCreateAction(
                query: "dark",
                matchingMoods: [matchingMood],
                selectedCount: 0,
                maximumSelectionCount: 5
            ) == false
        )
        #expect(
            StyleMoodPickerPolicy.shouldShowCreateAction(
                query: "새 스타일",
                matchingMoods: [],
                selectedCount: 5,
                maximumSelectionCount: 5
            ) == false
        )
    }
}

private final class StyleMoodRepositoryStub: StyleMoodRepositoryProtocol {
    private let moods: [StyleMood]

    init(
        moods: [StyleMood] = [
            StyleMood(
                id: "new_mood",
                displayName: "뉴 무드",
                displayGroup: .street,
                sortOrder: 300,
                isFeaturedInOnboarding: false
            )
        ]
    ) {
        self.moods = moods
    }

    func fetchOnboardingMoods() async throws -> [StyleMood] {
        moods
    }

    func fetchAllMoods() async throws -> [StyleMood] {
        try await fetchOnboardingMoods()
    }
}

private final class StyleMoodAdminRepositoryStub: StyleMoodAdminRepositoryProtocol {
    private(set) var createdDrafts: [StyleMoodMutationDraft] = []

    func createMood(_ draft: StyleMoodMutationDraft) async throws -> String {
        createdDrafts.append(draft)
        return "new_mood"
    }

    func updateMood(
        moodID: String,
        draft: StyleMoodMutationDraft,
        status: StyleMoodStatus
    ) async throws {}
}
