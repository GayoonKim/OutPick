import Foundation

struct StyleMood: Identifiable, Hashable, Equatable {
    let id: String
    let displayName: String
    let displayGroup: StyleMoodGroup
    let sortOrder: Int
    let isFeaturedInOnboarding: Bool
}
