import Foundation

@MainActor
final class StylePreferenceEditViewModel {
    struct State: Equatable {
        var moods: [StyleMood] = []
        var visibleMoods: [StyleMood] = []
        var selectedMoodIDs: Set<String>
        var searchQuery = ""
        var isLoading = false
        var isSaving = false
        var isSaveEnabled = false
        var selectionText = "0 / 5"
        var errorMessage: String?
        var emptyMessage: String?
    }

    private(set) var state: State {
        didSet { onStateChanged?(state) }
    }

    var onStateChanged: ((State) -> Void)?

    private let initialMoodIDs: Set<String>
    private let moodRepository: StyleMoodRepositoryProtocol
    private let updateUseCase: UpdateStylePreferencesUseCase
    private let onSaved: ([String], [StyleMood]) -> Void

    init(
        initialMoodIDs: [String],
        moodRepository: StyleMoodRepositoryProtocol,
        updateUseCase: UpdateStylePreferencesUseCase,
        onSaved: @escaping ([String], [StyleMood]) -> Void
    ) {
        let selected = Set(initialMoodIDs)
        self.initialMoodIDs = selected
        state = State(selectedMoodIDs: selected)
        self.moodRepository = moodRepository
        self.updateUseCase = updateUseCase
        self.onSaved = onSaved
        recompute()
    }

    func load() {
        Task { await loadMoods() }
    }

    func loadMoods() async {
        guard state.isLoading == false, state.moods.isEmpty else { return }
        state.isLoading = true
        state.errorMessage = nil
        do {
            state.moods = try await moodRepository.fetchOnboardingMoods()
            state.isLoading = false
            applyFilter()
        } catch {
            state.isLoading = false
            state.errorMessage = "관심 스타일을 불러오지 못했어요"
        }
    }

    func setSearchQuery(_ query: String) {
        state.searchQuery = query
        state.errorMessage = nil
        applyFilter()
    }

    func toggleMood(id: String) {
        guard state.isSaving == false else { return }
        if state.selectedMoodIDs.contains(id) {
            state.selectedMoodIDs.remove(id)
        } else if state.selectedMoodIDs.count < 5 {
            state.selectedMoodIDs.insert(id)
        } else {
            state.errorMessage = "관심 스타일은 최대 5개까지 선택할 수 있어요"
        }
        recompute()
    }

    func saveTapped() {
        Task { await save() }
    }

    func save() async {
        guard state.isSaveEnabled, state.isSaving == false else { return }
        state.isSaving = true
        state.errorMessage = nil
        recompute()
        let selectedIDs = state.moods
            .filter { state.selectedMoodIDs.contains($0.id) }
            .map(\.id)
        do {
            try await updateUseCase.execute(selectedMoodIDs: selectedIDs)
            state.isSaving = false
            recompute()
            onSaved(selectedIDs, state.moods)
        } catch {
            state.isSaving = false
            state.errorMessage = "관심 스타일을 저장하지 못했어요"
            recompute()
        }
    }

    private func recompute() {
        state.selectionText = "\(state.selectedMoodIDs.count) / 5"
        state.isSaveEnabled = state.selectedMoodIDs.isEmpty == false &&
            state.selectedMoodIDs != initialMoodIDs &&
            state.isSaving == false
    }

    private func applyFilter() {
        let query = state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        state.visibleMoods = query.isEmpty
            ? state.moods
            : state.moods.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
        state.emptyMessage = state.visibleMoods.isEmpty ? "검색 결과가 없어요" : nil
        recompute()
    }
}
