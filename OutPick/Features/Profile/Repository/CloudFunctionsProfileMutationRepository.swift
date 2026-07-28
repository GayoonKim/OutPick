import Foundation

final class CloudFunctionsProfileMutationRepository: ProfileMutationRepositoryProtocol {
    private let transport: CloudFunctionsTransporting

    init(transport: CloudFunctionsTransporting) {
        self.transport = transport
    }

    func checkNicknameAvailability(nickname: String) async throws -> Bool {
        let response = try await transport.call(
            "checkNicknameAvailability",
            data: ["nickname": nickname]
        )
        return try CloudFunctionResponseDecoder(dictionary: response).bool("isAvailable")
    }

    func completeOnboarding(
        nickname: String,
        selectedMoodIDs: [String]
    ) async throws -> CompleteOnboardingMutationResult {
        let response = try await transport.call(
            "completeOnboarding",
            data: [
                "nickname": nickname,
                "selectedMoodIDs": selectedMoodIDs
            ]
        )
        let decoder = CloudFunctionResponseDecoder(dictionary: response)
        return CompleteOnboardingMutationResult(
            userID: try decoder.string("userID"),
            onboardingVersion: try decoder.int("onboardingVersion")
        )
    }

    func updatePublicProfile(
        nickname: String?,
        avatarMutation: ProfileAvatarPathMutation
    ) async throws -> UserPublicProfile {
        var data: [String: Any] = [:]
        if let nickname {
            data["nickname"] = nickname
        }
        switch avatarMutation {
        case .unchanged:
            break
        case .set(let thumbPath, let originalPath):
            data["avatarThumbPath"] = thumbPath
            data["avatarOriginalPath"] = originalPath
        case .remove:
            data["avatarThumbPath"] = NSNull()
            data["avatarOriginalPath"] = NSNull()
        }

        let response = try await transport.call("updatePublicProfile", data: data)
        let decoder = CloudFunctionResponseDecoder(dictionary: response)
        return UserPublicProfile(
            userID: try decoder.string("userID"),
            nickname: try decoder.string("nickname"),
            avatarThumbPath: decoder.optionalString("avatarThumbPath"),
            avatarOriginalPath: decoder.optionalString("avatarOriginalPath"),
            createdAt: nil,
            updatedAt: nil
        )
    }

    func updateStylePreferences(selectedMoodIDs: [String]) async throws {
        _ = try await transport.call(
            "updateStylePreferences",
            data: ["selectedMoodIDs": selectedMoodIDs]
        )
    }
}
