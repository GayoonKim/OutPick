import Foundation

struct CompleteOnboardingMutationResult: Equatable {
    let userID: String
    let onboardingVersion: Int
}

enum ProfileAvatarPathMutation: Equatable {
    case unchanged
    case set(thumbPath: String, originalPath: String)
    case remove
}

protocol ProfileMutationRepositoryProtocol {
    func checkNicknameAvailability(nickname: String) async throws -> Bool

    func completeOnboarding(
        nickname: String,
        selectedMoodIDs: [String]
    ) async throws -> CompleteOnboardingMutationResult

    func updatePublicProfile(
        nickname: String?,
        avatarMutation: ProfileAvatarPathMutation
    ) async throws -> UserPublicProfile

    func updateStylePreferences(selectedMoodIDs: [String]) async throws
}
