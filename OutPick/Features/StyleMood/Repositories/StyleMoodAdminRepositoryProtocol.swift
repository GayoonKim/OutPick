import Foundation

struct StyleMoodMutationDraft: Equatable {
    var moodID: String?
    var displayName: String
    var displayGroup: StyleMoodGroup
    var aliases: [String]
    var sortOrder: Int?
    var isFeaturedInOnboarding: Bool
}

protocol StyleMoodAdminRepositoryProtocol {
    func createMood(_ draft: StyleMoodMutationDraft) async throws -> String
    func updateMood(
        moodID: String,
        draft: StyleMoodMutationDraft,
        status: StyleMoodStatus
    ) async throws
}
