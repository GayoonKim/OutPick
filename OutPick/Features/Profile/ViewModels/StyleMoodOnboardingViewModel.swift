import Foundation

@MainActor
final class StyleMoodOnboardingViewModel {
    struct State: Equatable {
        var moods: [StyleMood] = []
        var visibleMoods: [StyleMood] = []
        var selectedMoodIDs: Set<String> = []
        var searchQuery = ""
        var isLoading = false
        var isSaving = false
        var isCompleteEnabled = false
        var selectionText = "0 / 5"
        var errorMessage: String?
        var emptyMessage: String?
    }

    private(set) var state = State() {
        didSet { onStateChanged?(state) }
    }

    var onStateChanged: ((State) -> Void)?

    private let userID: String
    private let draft: OnboardingDraft
    private let moodRepository: StyleMoodRepositoryProtocol
    private let completeOnboardingUseCase: CompleteOnboardingUseCase
    private let onBack: () -> Void
    private let onCompleted: (CompleteOnboardingOutcome) -> Void

    init(
        userID: String,
        draft: OnboardingDraft,
        moodRepository: StyleMoodRepositoryProtocol,
        completeOnboardingUseCase: CompleteOnboardingUseCase,
        onBack: @escaping () -> Void,
        onCompleted: @escaping (CompleteOnboardingOutcome) -> Void
    ) {
        self.userID = userID
        self.draft = draft
        self.moodRepository = moodRepository
        self.completeOnboardingUseCase = completeOnboardingUseCase
        self.onBack = onBack
        self.onCompleted = onCompleted
    }

    func load() {
        Task { await loadMoods() }
    }

    func loadMoods() async {
        guard state.isLoading == false, state.moods.isEmpty else { return }
        state.isLoading = true
        state.errorMessage = nil

        do {
            let moods = try await moodRepository.fetchOnboardingMoods()
            state.moods = moods
            applyMoodFilter()
            state.isLoading = false
            if moods.isEmpty {
                state.errorMessage = "선택 가능한 관심 스타일이 없어요"
            }
        } catch {
            state.isLoading = false
            state.errorMessage = "관심 스타일을 불러오지 못했어요"
        }
    }

    func retryLoad() {
        state.moods = []
        state.visibleMoods = []
        load()
    }

    func toggleMood(id: String) {
        guard state.isSaving == false,
              state.moods.contains(where: { $0.id == id }) else {
            return
        }

        if state.selectedMoodIDs.contains(id) {
            state.selectedMoodIDs.remove(id)
            state.errorMessage = nil
        } else if state.selectedMoodIDs.count < 5 {
            state.selectedMoodIDs.insert(id)
            state.errorMessage = nil
        } else {
            state.errorMessage = "관심 스타일은 최대 5개까지 선택할 수 있어요"
        }
        recompute()
    }

    func setSearchQuery(_ query: String) {
        state.searchQuery = query
        state.errorMessage = nil
        applyMoodFilter()
    }

    func backTapped() {
        guard state.isSaving == false else { return }
        onBack()
    }

    func completeTapped() {
        Task { await complete() }
    }

    func complete() async {
        guard state.isCompleteEnabled, state.isSaving == false else { return }
        state.isSaving = true
        state.errorMessage = nil
        recompute()

        let selectedIDs = state.moods
            .filter { state.selectedMoodIDs.contains($0.id) }
            .map(\.id)

        do {
            let outcome = try await completeOnboardingUseCase.execute(
                userID: userID,
                draft: draft,
                selectedMoodIDs: selectedIDs
            )
            state.isSaving = false
            recompute()
            onCompleted(outcome)
        } catch {
            state.isSaving = false
            state.errorMessage = "온보딩을 완료하지 못했어요 잠시 후 다시 시도해 주세요"
            recompute()
        }
    }

    private func recompute() {
        state.selectionText = "\(state.selectedMoodIDs.count) / 5"
        state.isCompleteEnabled = state.selectedMoodIDs.isEmpty == false && state.isSaving == false
    }

    private func applyMoodFilter() {
        let query = state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            state.visibleMoods = state.moods.filter(\.isFeaturedInOnboarding)
            state.emptyMessage = state.visibleMoods.isEmpty
                ? "선택 가능한 관심 스타일이 없어요"
                : nil
        } else {
            state.visibleMoods = state.moods.filter {
                $0.displayName.localizedCaseInsensitiveContains(query)
            }
            state.emptyMessage = state.visibleMoods.isEmpty
                ? "검색 결과가 없어요"
                : nil
        }
    }
}
