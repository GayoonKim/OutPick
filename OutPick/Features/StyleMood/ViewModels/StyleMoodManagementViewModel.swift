import Foundation

@MainActor
final class StyleMoodManagementViewModel: ObservableObject {
    @Published private(set) var moods: [StyleMood] = []
    @Published var searchText = ""
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var message: String?

    private let moodRepository: StyleMoodRepositoryProtocol
    private let adminRepository: StyleMoodAdminRepositoryProtocol

    init(
        moodRepository: StyleMoodRepositoryProtocol,
        adminRepository: StyleMoodAdminRepositoryProtocol
    ) {
        self.moodRepository = moodRepository
        self.adminRepository = adminRepository
    }

    func load() async {
        isLoading = true
        message = nil
        defer { isLoading = false }
        do {
            moods = try await moodRepository.fetchAllMoods()
        } catch {
            message = "스타일 키워드를 불러오지 못했습니다: \(error.localizedDescription)"
        }
    }

    func visibleMoods(in group: StyleMoodGroup) -> [StyleMood] {
        moods.filter {
            $0.displayGroup == group && $0.matchesSearchQuery(searchText)
        }
    }

    func save(
        existingMood: StyleMood?,
        draft: StyleMoodMutationDraft,
        status: StyleMoodStatus
    ) async -> StyleMood? {
        guard isSaving == false else { return nil }
        let name = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else {
            message = "스타일 키워드 이름을 입력해주세요"
            return nil
        }

        isSaving = true
        message = nil
        defer { isSaving = false }

        let normalizedDraft = StyleMoodMutationDraft(
            moodID: draft.moodID,
            displayName: name,
            displayGroup: draft.displayGroup,
            aliases: normalizedAliases(draft.aliases),
            sortOrder: draft.sortOrder,
            isFeaturedInOnboarding: draft.isFeaturedInOnboarding
        )

        do {
            let moodID: String
            if let existingMood {
                moodID = existingMood.id
                try await adminRepository.updateMood(
                    moodID: moodID,
                    draft: normalizedDraft,
                    status: status
                )
            } else {
                moodID = try await adminRepository.createMood(normalizedDraft)
            }
            await load()
            return moods.first(where: { $0.id == moodID })
        } catch {
            message = "스타일 키워드를 저장하지 못했습니다: \(error.localizedDescription)"
            return nil
        }
    }

    private func normalizedAliases(_ aliases: [String]) -> [String] {
        var seen = Set<String>()
        return aliases.compactMap { alias in
            let value = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.isEmpty == false else { return nil }
            let key = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return seen.insert(key).inserted ? value : nil
        }
    }
}
