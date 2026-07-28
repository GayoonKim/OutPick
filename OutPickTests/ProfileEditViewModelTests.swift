import Testing
import UIKit
@testable import OutPick

struct ProfileEditViewModelTests {
    @Test
    @MainActor
    func unchangedProfileCannotSave() {
        let viewModel = makeViewModel()
        #expect(viewModel.state.isSaveEnabled == false)
    }

    @Test
    @MainActor
    func removeAvatarEnablesSaveAndProducesNilPaths() async {
        let repository = ProfileEditViewModelMutationFake()
        let viewModel = makeViewModel(repository: repository)
        viewModel.removeAvatar()

        #expect(viewModel.state.isSaveEnabled)
        await viewModel.save()
        #expect(repository.avatarMutations == [.remove])
    }

    @Test
    @MainActor
    func unavailableNicknameKeepsEditorWithError() async {
        let repository = ProfileEditViewModelMutationFake(isNicknameAvailable: false)
        let viewModel = makeViewModel(repository: repository)
        viewModel.setNickname("새닉네임")
        await viewModel.save()

        #expect(viewModel.state.errorMessage == "이미 사용 중인 닉네임이에요")
    }

    @Test
    @MainActor
    func mutationFailureKeepsInputAndAllowsRetry() async {
        let repository = ProfileEditViewModelMutationFake(updateError: ProfileEditTestError.failed)
        let viewModel = makeViewModel(repository: repository)
        viewModel.setNickname("재시도닉네임")

        await viewModel.save()

        #expect(viewModel.state.nickname == "재시도닉네임")
        #expect(viewModel.state.errorMessage == "프로필을 저장하지 못했어요")
        #expect(viewModel.state.isSaving == false)
        #expect(viewModel.state.isSaveEnabled)
    }

    @Test
    @MainActor
    func nicknameAvailabilityNetworkFailureKeepsInputAndSkipsMutation() async {
        let repository = ProfileEditViewModelMutationFake(
            availabilityError: ProfileEditTestError.failed
        )
        let viewModel = makeViewModel(repository: repository)
        viewModel.setNickname("확인재시도")

        await viewModel.save()

        #expect(viewModel.state.nickname == "확인재시도")
        #expect(viewModel.state.errorMessage == "프로필을 저장하지 못했어요")
        #expect(viewModel.state.isSaveEnabled)
        #expect(repository.updateCallCount == 0)
    }

    @Test
    @MainActor
    func repeatedSaveWhileMutationIsInFlightCallsMutationOnce() async throws {
        let repository = ProfileEditViewModelMutationFake(updateDelayNanoseconds: 150_000_000)
        let viewModel = makeViewModel(repository: repository)
        viewModel.setNickname("한번만저장")

        viewModel.saveTapped()
        viewModel.saveTapped()
        try await Task.sleep(nanoseconds: 250_000_000)

        #expect(repository.updateCallCount == 1)
    }

    @MainActor
    private func makeViewModel(
        repository: ProfileEditViewModelMutationFake = ProfileEditViewModelMutationFake()
    ) -> ProfileEditViewModel {
        ProfileEditViewModel(
            currentProfile: UserPublicProfile(
                userID: "user-1",
                nickname: "기존닉네임",
                avatarThumbPath: "old-thumb",
                avatarOriginalPath: "old-original",
                createdAt: nil,
                updatedAt: nil
            ),
            updateUseCase: UpdatePublicProfileUseCase(
                mutationRepository: repository,
                avatarUploader: ProfileEditViewModelAvatarFake(),
                cleanupStore: ProfileEditViewModelCleanupFake()
            ),
            onSaved: { _ in }
        )
    }
}

private final class ProfileEditViewModelMutationFake: ProfileMutationRepositoryProtocol {
    let isNicknameAvailable: Bool
    let availabilityError: Error?
    let updateError: Error?
    let updateDelayNanoseconds: UInt64
    var avatarMutations: [ProfileAvatarPathMutation] = []
    var updateCallCount = 0

    init(
        isNicknameAvailable: Bool = true,
        availabilityError: Error? = nil,
        updateError: Error? = nil,
        updateDelayNanoseconds: UInt64 = 0
    ) {
        self.isNicknameAvailable = isNicknameAvailable
        self.availabilityError = availabilityError
        self.updateError = updateError
        self.updateDelayNanoseconds = updateDelayNanoseconds
    }

    func checkNicknameAvailability(nickname: String) async throws -> Bool {
        if let availabilityError { throw availabilityError }
        return isNicknameAvailable
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
        updateCallCount += 1
        if updateDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: updateDelayNanoseconds)
        }
        if let updateError { throw updateError }
        avatarMutations.append(avatarMutation)
        return UserPublicProfile(
            userID: "user-1",
            nickname: nickname ?? "기존닉네임",
            avatarThumbPath: avatarMutation == .remove ? nil : "old-thumb",
            avatarOriginalPath: avatarMutation == .remove ? nil : "old-original",
            createdAt: nil,
            updatedAt: nil
        )
    }

    func updateStylePreferences(selectedMoodIDs: [String]) async throws {}
}

private final class ProfileEditViewModelAvatarFake: ProfileAvatarUploading {
    func upload(
        userID: String,
        avatar: OnboardingAvatarDraft
    ) async throws -> UploadedProfileAvatar {
        UploadedProfileAvatar(thumbPath: "new-thumb", originalPath: "new-original")
    }

    func delete(paths: [String]) async throws {}
}

private final class ProfileEditViewModelCleanupFake: ProfileAvatarCleanupStoring {
    var pendingPaths: [String] = []
    func enqueue(paths: [String]) { pendingPaths.append(contentsOf: paths) }
    func remove(paths: [String]) {}
}

private enum ProfileEditTestError: Error {
    case failed
}
