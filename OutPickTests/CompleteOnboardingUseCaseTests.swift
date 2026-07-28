import Foundation
import Testing
import UIKit
@testable import OutPick

struct CompleteOnboardingUseCaseTests {
    @Test
    func onboardingWithoutAvatarDoesNotUploadImage() async throws {
        let mutation = ProfileMutationRepositoryFake()
        let uploader = ProfileAvatarUploaderFake()
        let useCase = CompleteOnboardingUseCase(
            mutationRepository: mutation,
            avatarUploader: uploader
        )

        let outcome = try await useCase.execute(
            userID: "user-1",
            draft: OnboardingDraft(nickname: "아웃피커", avatar: nil),
            selectedMoodIDs: ["minimal"]
        )

        #expect(uploader.uploadedUserIDs.isEmpty)
        #expect(outcome.avatarUploadFailed == false)
        #expect(outcome.publicProfile.nickname == "아웃피커")
    }

    @Test
    func avatarFailureKeepsCompletedAccountAndReportsPartialFailure() async throws {
        let uploader = ProfileAvatarUploaderFake(error: TestError.failed)
        let useCase = CompleteOnboardingUseCase(
            mutationRepository: ProfileMutationRepositoryFake(),
            avatarUploader: uploader
        )

        let outcome = try await useCase.execute(
            userID: "user-1",
            draft: makeDraftWithAvatar(),
            selectedMoodIDs: ["minimal"]
        )

        #expect(outcome.account.accountStatus == .active)
        #expect(outcome.avatarUploadFailed)
        #expect(outcome.publicProfile.avatarThumbPath == nil)
    }

    @Test
    func uploadedAvatarPathsArePersistedToPublicProfile() async throws {
        let mutation = ProfileMutationRepositoryFake()
        let uploader = ProfileAvatarUploaderFake(
            result: UploadedProfileAvatar(
                thumbPath: "profileImages/user-1/thumb/a.jpg",
                originalPath: "profileImages/user-1/original/a.jpg"
            )
        )
        let useCase = CompleteOnboardingUseCase(
            mutationRepository: mutation,
            avatarUploader: uploader
        )

        let outcome = try await useCase.execute(
            userID: "user-1",
            draft: makeDraftWithAvatar(),
            selectedMoodIDs: ["minimal"]
        )

        #expect(mutation.updatedAvatarThumbPath == "profileImages/user-1/thumb/a.jpg")
        #expect(mutation.updatedAvatarOriginalPath == "profileImages/user-1/original/a.jpg")
        #expect(outcome.avatarUploadFailed == false)
    }

    private func makeDraftWithAvatar() -> OnboardingDraft {
        OnboardingDraft(
            nickname: "아웃피커",
            avatar: OnboardingAvatarDraft(
                thumbnail: UIImage(),
                originalFileURL: URL(fileURLWithPath: "/tmp/profile.jpg"),
                sha256: "sha"
            )
        )
    }
}

final class ProfileMutationRepositoryFake: ProfileMutationRepositoryProtocol {
    var completedMoodIDs: [String] = []
    var updatedAvatarThumbPath: String?
    var updatedAvatarOriginalPath: String?

    func checkNicknameAvailability(nickname: String) async throws -> Bool {
        true
    }

    func completeOnboarding(
        nickname: String,
        selectedMoodIDs: [String]
    ) async throws -> CompleteOnboardingMutationResult {
        completedMoodIDs = selectedMoodIDs
        return CompleteOnboardingMutationResult(userID: "user-1", onboardingVersion: 1)
    }

    func updatePublicProfile(
        nickname: String?,
        avatarMutation: ProfileAvatarPathMutation
    ) async throws -> UserPublicProfile {
        if case .set(let thumbPath, let originalPath) = avatarMutation {
            updatedAvatarThumbPath = thumbPath
            updatedAvatarOriginalPath = originalPath
        }
        return UserPublicProfile(
            userID: "user-1",
            nickname: nickname ?? "아웃피커",
            avatarThumbPath: updatedAvatarThumbPath,
            avatarOriginalPath: updatedAvatarOriginalPath,
            createdAt: nil,
            updatedAt: nil
        )
    }

    func updateStylePreferences(selectedMoodIDs: [String]) async throws {}
}

final class ProfileAvatarUploaderFake: ProfileAvatarUploading {
    private let result: UploadedProfileAvatar
    private let error: Error?
    private(set) var uploadedUserIDs: [String] = []

    init(
        result: UploadedProfileAvatar = UploadedProfileAvatar(
            thumbPath: "profileImages/user-1/thumb/default.jpg",
            originalPath: "profileImages/user-1/original/default.jpg"
        ),
        error: Error? = nil
    ) {
        self.result = result
        self.error = error
    }

    func upload(
        userID: String,
        avatar: OnboardingAvatarDraft
    ) async throws -> UploadedProfileAvatar {
        uploadedUserIDs.append(userID)
        if let error {
            throw error
        }
        return result
    }

    func delete(paths: [String]) async throws {}
}

private enum TestError: Error {
    case failed
}
