import Foundation
import Testing
import UIKit
@testable import OutPick

struct UpdatePublicProfileUseCaseTests {
    @Test
    func removeClearsPathsThenDeletesOldObjects() async throws {
        let mutation = ProfileEditMutationFake()
        let avatar = ProfileEditAvatarFake()
        let cleanup = ProfileAvatarCleanupStoreFake()
        let useCase = UpdatePublicProfileUseCase(
            mutationRepository: mutation,
            avatarUploader: avatar,
            cleanupStore: cleanup
        )

        let outcome = try await useCase.execute(
            currentProfile: makeProfile(),
            nickname: "기존닉네임",
            avatarEdit: .remove
        )

        #expect(mutation.avatarMutations == [.remove])
        #expect(Set(avatar.deletedPaths) == Set(["old-thumb", "old-original"]))
        #expect(outcome.profile.avatarThumbPath == nil)
        #expect(outcome.oldAvatarCleanupFailed == false)
    }

    @Test
    func replacementUploadsBeforeMutationAndDeletesOldObjects() async throws {
        let events = EventRecorder()
        let mutation = ProfileEditMutationFake(events: events)
        let avatar = ProfileEditAvatarFake(events: events)
        let cleanup = ProfileAvatarCleanupStoreFake()
        let useCase = UpdatePublicProfileUseCase(
            mutationRepository: mutation,
            avatarUploader: avatar,
            cleanupStore: cleanup
        )

        _ = try await useCase.execute(
            currentProfile: makeProfile(),
            nickname: "기존닉네임",
            avatarEdit: .replace(makeDraft())
        )

        #expect(events.values == ["upload", "mutation", "delete"])
    }

    @Test
    func cleanupFailureKeepsUpdatedProfileAndReportsPartialFailure() async throws {
        let mutation = ProfileEditMutationFake()
        let avatar = ProfileEditAvatarFake(deleteError: TestError.failed)
        let cleanup = ProfileAvatarCleanupStoreFake()
        let useCase = UpdatePublicProfileUseCase(
            mutationRepository: mutation,
            avatarUploader: avatar,
            cleanupStore: cleanup
        )

        let outcome = try await useCase.execute(
            currentProfile: makeProfile(),
            nickname: "기존닉네임",
            avatarEdit: .remove
        )

        #expect(outcome.profile.avatarThumbPath == nil)
        #expect(outcome.oldAvatarCleanupFailed)
        #expect(Set(cleanup.pendingPaths) == Set(["old-thumb", "old-original"]))
    }

    @Test
    func unavailableNicknameStopsBeforeMutation() async {
        let mutation = ProfileEditMutationFake(isNicknameAvailable: false)
        let avatar = ProfileEditAvatarFake()
        let cleanup = ProfileAvatarCleanupStoreFake()
        let useCase = UpdatePublicProfileUseCase(
            mutationRepository: mutation,
            avatarUploader: avatar,
            cleanupStore: cleanup
        )

        await #expect(throws: UpdatePublicProfileError.nicknameUnavailable) {
            try await useCase.execute(
                currentProfile: makeProfile(),
                nickname: "새닉네임",
                avatarEdit: .unchanged
            )
        }
        #expect(mutation.avatarMutations.isEmpty)
    }

    @Test
    func uploadFailureStopsBeforeProfileMutation() async {
        let mutation = ProfileEditMutationFake()
        let avatar = ProfileEditAvatarFake(uploadError: TestError.failed)
        let useCase = UpdatePublicProfileUseCase(
            mutationRepository: mutation,
            avatarUploader: avatar,
            cleanupStore: ProfileAvatarCleanupStoreFake()
        )

        await #expect(throws: TestError.failed) {
            try await useCase.execute(
                currentProfile: makeProfile(),
                nickname: "기존닉네임",
                avatarEdit: .replace(makeDraft())
            )
        }

        #expect(mutation.avatarMutations.isEmpty)
        #expect(avatar.deletedPaths.isEmpty)
    }

    @Test
    func mutationFailureDeletesTheNewlyUploadedObjects() async {
        let mutation = ProfileEditMutationFake(updateError: TestError.failed)
        let avatar = ProfileEditAvatarFake()
        let cleanup = ProfileAvatarCleanupStoreFake()
        let useCase = UpdatePublicProfileUseCase(
            mutationRepository: mutation,
            avatarUploader: avatar,
            cleanupStore: cleanup
        )

        await #expect(throws: TestError.failed) {
            try await useCase.execute(
                currentProfile: makeProfile(),
                nickname: "기존닉네임",
                avatarEdit: .replace(makeDraft())
            )
        }

        #expect(Set(avatar.deletedPaths) == Set(["new-thumb", "new-original"]))
        #expect(cleanup.pendingPaths.isEmpty)
    }

    @Test
    func failedPendingCleanupRetryKeepsStoredPaths() async {
        let pendingPaths = ["pending-thumb", "pending-original"]
        let cleanup = ProfileAvatarCleanupStoreFake(pendingPaths: pendingPaths)
        let useCase = UpdatePublicProfileUseCase(
            mutationRepository: ProfileEditMutationFake(),
            avatarUploader: ProfileEditAvatarFake(deleteError: TestError.failed),
            cleanupStore: cleanup
        )

        await useCase.retryPendingCleanup()

        #expect(Set(cleanup.pendingPaths) == Set(pendingPaths))
    }

    @Test
    func retryPendingCleanupDeletesAndClearsStoredPaths() async {
        let mutation = ProfileEditMutationFake()
        let avatar = ProfileEditAvatarFake()
        let cleanup = ProfileAvatarCleanupStoreFake(
            pendingPaths: ["pending-thumb", "pending-original"]
        )
        let useCase = UpdatePublicProfileUseCase(
            mutationRepository: mutation,
            avatarUploader: avatar,
            cleanupStore: cleanup
        )

        await useCase.retryPendingCleanup()

        #expect(Set(avatar.deletedPaths) == Set(["pending-thumb", "pending-original"]))
        #expect(cleanup.pendingPaths.isEmpty)
    }

    private func makeProfile() -> UserPublicProfile {
        UserPublicProfile(
            userID: "user-1",
            nickname: "기존닉네임",
            avatarThumbPath: "old-thumb",
            avatarOriginalPath: "old-original",
            createdAt: nil,
            updatedAt: nil
        )
    }

    private func makeDraft() -> OnboardingAvatarDraft {
        OnboardingAvatarDraft(
            thumbnail: UIImage(),
            originalFileURL: URL(fileURLWithPath: "/tmp/avatar.jpg"),
            sha256: "sha"
        )
    }
}

private final class EventRecorder: @unchecked Sendable {
    var values: [String] = []
}

private final class ProfileEditMutationFake: ProfileMutationRepositoryProtocol {
    let isNicknameAvailable: Bool
    let events: EventRecorder?
    let updateError: Error?
    var avatarMutations: [ProfileAvatarPathMutation] = []

    init(
        isNicknameAvailable: Bool = true,
        events: EventRecorder? = nil,
        updateError: Error? = nil
    ) {
        self.isNicknameAvailable = isNicknameAvailable
        self.events = events
        self.updateError = updateError
    }

    func checkNicknameAvailability(nickname: String) async throws -> Bool {
        isNicknameAvailable
    }

    func completeOnboarding(
        nickname: String,
        selectedMoodIDs: [String]
    ) async throws -> CompleteOnboardingMutationResult {
        fatalError("사용하지 않음")
    }

    func updatePublicProfile(
        nickname: String?,
        avatarMutation: ProfileAvatarPathMutation
    ) async throws -> UserPublicProfile {
        events?.values.append("mutation")
        avatarMutations.append(avatarMutation)
        if let updateError { throw updateError }
        let paths: (String?, String?)
        switch avatarMutation {
        case .unchanged:
            paths = ("old-thumb", "old-original")
        case .set(let thumbPath, let originalPath):
            paths = (thumbPath, originalPath)
        case .remove:
            paths = (nil, nil)
        }
        return UserPublicProfile(
            userID: "user-1",
            nickname: nickname ?? "기존닉네임",
            avatarThumbPath: paths.0,
            avatarOriginalPath: paths.1,
            createdAt: nil,
            updatedAt: nil
        )
    }

    func updateStylePreferences(selectedMoodIDs: [String]) async throws {}
}

private final class ProfileEditAvatarFake: ProfileAvatarUploading {
    let events: EventRecorder?
    let deleteError: Error?
    let uploadError: Error?
    var deletedPaths: [String] = []

    init(
        events: EventRecorder? = nil,
        deleteError: Error? = nil,
        uploadError: Error? = nil
    ) {
        self.events = events
        self.deleteError = deleteError
        self.uploadError = uploadError
    }

    func upload(
        userID: String,
        avatar: OnboardingAvatarDraft
    ) async throws -> UploadedProfileAvatar {
        events?.values.append("upload")
        if let uploadError { throw uploadError }
        return UploadedProfileAvatar(
            thumbPath: "new-thumb",
            originalPath: "new-original"
        )
    }

    func delete(paths: [String]) async throws {
        events?.values.append("delete")
        deletedPaths.append(contentsOf: paths)
        if let deleteError { throw deleteError }
    }
}

private enum TestError: Error {
    case failed
}

private final class ProfileAvatarCleanupStoreFake: ProfileAvatarCleanupStoring {
    var pendingPaths: [String]

    init(pendingPaths: [String] = []) {
        self.pendingPaths = pendingPaths
    }

    func enqueue(paths: [String]) {
        pendingPaths = Array(Set(pendingPaths + paths))
    }

    func remove(paths: [String]) {
        let removed = Set(paths)
        pendingPaths.removeAll { removed.contains($0) }
    }
}
