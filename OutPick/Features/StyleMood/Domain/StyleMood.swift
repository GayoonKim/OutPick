import Foundation

enum StyleMoodStatus: String, Hashable {
    case active
    case inactive
}

struct StyleMood: Identifiable, Hashable, Equatable {
    let id: String
    let displayName: String
    let displayGroup: StyleMoodGroup
    let aliases: [String]
    let sortOrder: Int
    let isFeaturedInOnboarding: Bool
    let status: StyleMoodStatus

    init(
        id: String,
        displayName: String,
        displayGroup: StyleMoodGroup,
        aliases: [String] = [],
        sortOrder: Int,
        isFeaturedInOnboarding: Bool,
        status: StyleMoodStatus = .active
    ) {
        self.id = id
        self.displayName = displayName
        self.displayGroup = displayGroup
        self.aliases = aliases
        self.sortOrder = sortOrder
        self.isFeaturedInOnboarding = isFeaturedInOnboarding
        self.status = status
    }
}

extension StyleMood {
    func matchesSearchQuery(_ rawQuery: String) -> Bool {
        let query = rawQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        guard query.isEmpty == false else { return true }

        return ([displayName] + aliases).contains { term in
            term.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            .contains(query)
        }
    }
}

enum StyleMoodPickerPolicy {
    static func searchResults(
        in moods: [StyleMood],
        query rawQuery: String
    ) -> [StyleMood] {
        guard normalizedQuery(rawQuery).isEmpty == false else { return [] }

        return moods.filter {
            $0.status == .active && $0.matchesSearchQuery(rawQuery)
        }
    }

    static func shouldShowCreateAction(
        query rawQuery: String,
        matchingMoods: [StyleMood],
        selectedCount: Int,
        maximumSelectionCount: Int
    ) -> Bool {
        normalizedQuery(rawQuery).isEmpty == false &&
        matchingMoods.isEmpty &&
        selectedCount < maximumSelectionCount
    }

    static func normalizedQuery(_ rawQuery: String) -> String {
        rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
