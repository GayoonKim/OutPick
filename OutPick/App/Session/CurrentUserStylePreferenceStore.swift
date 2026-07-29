import Combine
import Foundation

@MainActor
final class CurrentUserStylePreferenceStore: ObservableObject {
    @Published private(set) var selectedMoodIDs: [String]

    init(selectedMoodIDs: [String] = []) {
        self.selectedMoodIDs = Self.normalized(selectedMoodIDs)
    }

    func replace(selectedMoodIDs: [String]) {
        let normalized = Self.normalized(selectedMoodIDs)
        guard normalized != self.selectedMoodIDs else { return }
        self.selectedMoodIDs = normalized
    }

    func clear() {
        replace(selectedMoodIDs: [])
    }

    private static func normalized(_ moodIDs: [String]) -> [String] {
        var seen = Set<String>()
        return moodIDs.compactMap { rawValue in
            let moodID = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard moodID.isEmpty == false, seen.insert(moodID).inserted else {
                return nil
            }
            return moodID
        }
    }
}
