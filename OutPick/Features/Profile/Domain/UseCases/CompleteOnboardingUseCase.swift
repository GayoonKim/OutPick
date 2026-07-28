import Foundation

struct CompleteOnboardingOutcome: Equatable {
    let account: UserAccount
    let publicProfile: UserPublicProfile
    let avatarUploadFailed: Bool
}

struct CompleteOnboardingUseCase {
    private let mutationRepository: ProfileMutationRepositoryProtocol
    private let avatarUploader: ProfileAvatarUploading

    init(
        mutationRepository: ProfileMutationRepositoryProtocol,
        avatarUploader: ProfileAvatarUploading
    ) {
        self.mutationRepository = mutationRepository
        self.avatarUploader = avatarUploader
    }

    func execute(
        userID: String,
        draft: OnboardingDraft,
        selectedMoodIDs: [String]
    ) async throws -> CompleteOnboardingOutcome {
        let mutation = try await mutationRepository.completeOnboarding(
            nickname: draft.nickname,
            selectedMoodIDs: selectedMoodIDs
        )
        guard mutation.userID == userID else {
            throw FirebaseError.FailedToSaveProfile
        }
        let account = UserAccount(
            userID: mutation.userID,
            onboardingVersion: mutation.onboardingVersion,
            selectedMoodIDs: selectedMoodIDs,
            accountStatus: .active,
            onboardingCompletedAt: Date(),
            createdAt: Date(),
            updatedAt: Date()
        )

        guard let avatar = draft.avatar else {
            return CompleteOnboardingOutcome(
                account: account,
                publicProfile: UserPublicProfile(
                    userID: mutation.userID,
                    nickname: draft.nickname,
                    avatarThumbPath: nil,
                    avatarOriginalPath: nil,
                    createdAt: Date(),
                    updatedAt: Date()
                ),
                avatarUploadFailed: false
            )
        }

        do {
            let uploaded = try await avatarUploader.upload(userID: userID, avatar: avatar)
            let publicProfile = try await mutationRepository.updatePublicProfile(
                nickname: nil,
                avatarMutation: .set(
                    thumbPath: uploaded.thumbPath,
                    originalPath: uploaded.originalPath
                )
            )
            return CompleteOnboardingOutcome(
                account: account,
                publicProfile: publicProfile,
                avatarUploadFailed: false
            )
        } catch {
            return CompleteOnboardingOutcome(
                account: account,
                publicProfile: UserPublicProfile(
                    userID: mutation.userID,
                    nickname: draft.nickname,
                    avatarThumbPath: nil,
                    avatarOriginalPath: nil,
                    createdAt: Date(),
                    updatedAt: Date()
                ),
                avatarUploadFailed: true
            )
        }
    }
}
