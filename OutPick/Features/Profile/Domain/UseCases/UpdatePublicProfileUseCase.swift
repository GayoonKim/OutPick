import Foundation

enum ProfileAvatarEdit {
    case unchanged
    case replace(OnboardingAvatarDraft)
    case remove
}

enum UpdatePublicProfileError: Error, Equatable {
    case nicknameUnavailable
}

struct UpdatePublicProfileOutcome: Equatable {
    let profile: UserPublicProfile
    let oldAvatarCleanupFailed: Bool
}

struct UpdatePublicProfileUseCase {
    private let mutationRepository: ProfileMutationRepositoryProtocol
    private let avatarUploader: ProfileAvatarUploading
    private let cleanupStore: ProfileAvatarCleanupStoring

    init(
        mutationRepository: ProfileMutationRepositoryProtocol,
        avatarUploader: ProfileAvatarUploading,
        cleanupStore: ProfileAvatarCleanupStoring = UserDefaultsProfileAvatarCleanupStore()
    ) {
        self.mutationRepository = mutationRepository
        self.avatarUploader = avatarUploader
        self.cleanupStore = cleanupStore
    }

    func retryPendingCleanup() async {
        let pendingPaths = cleanupStore.pendingPaths
        guard pendingPaths.isEmpty == false else { return }
        do {
            try await avatarUploader.delete(paths: pendingPaths)
            cleanupStore.remove(paths: pendingPaths)
        } catch {
            // 다음 마이페이지 진입 또는 프로필 저장 때 다시 시도한다.
        }
    }

    func execute(
        currentProfile: UserPublicProfile,
        nickname: String,
        avatarEdit: ProfileAvatarEdit
    ) async throws -> UpdatePublicProfileOutcome {
        let normalizedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let nicknamePatch = normalizedNickname == currentProfile.nickname ? nil : normalizedNickname

        if nicknamePatch != nil {
            let isAvailable = try await mutationRepository.checkNicknameAvailability(
                nickname: normalizedNickname
            )
            guard isAvailable else {
                throw UpdatePublicProfileError.nicknameUnavailable
            }
        }

        let oldPaths = [currentProfile.avatarThumbPath, currentProfile.avatarOriginalPath]
            .compactMap { $0 }
        let avatarMutation: ProfileAvatarPathMutation
        var newlyUploadedPaths: [String] = []

        switch avatarEdit {
        case .unchanged:
            avatarMutation = .unchanged
        case .remove:
            avatarMutation = .remove
        case .replace(let draft):
            let uploaded = try await avatarUploader.upload(
                userID: currentProfile.userID,
                avatar: draft
            )
            newlyUploadedPaths = [uploaded.thumbPath, uploaded.originalPath]
            avatarMutation = .set(
                thumbPath: uploaded.thumbPath,
                originalPath: uploaded.originalPath
            )
        }

        do {
            let profile = try await mutationRepository.updatePublicProfile(
                nickname: nicknamePatch,
                avatarMutation: avatarMutation
            )
            let pathsToDelete = oldPaths.filter { newlyUploadedPaths.contains($0) == false }
            guard avatarEdit.requiresOldPathCleanup, pathsToDelete.isEmpty == false else {
                return UpdatePublicProfileOutcome(
                    profile: profile,
                    oldAvatarCleanupFailed: false
                )
            }

            do {
                try await avatarUploader.delete(paths: pathsToDelete)
                return UpdatePublicProfileOutcome(
                    profile: profile,
                    oldAvatarCleanupFailed: false
                )
            } catch {
                cleanupStore.enqueue(paths: pathsToDelete)
                return UpdatePublicProfileOutcome(
                    profile: profile,
                    oldAvatarCleanupFailed: true
                )
            }
        } catch {
            if newlyUploadedPaths.isEmpty == false {
                do {
                    try await avatarUploader.delete(paths: newlyUploadedPaths)
                } catch {
                    cleanupStore.enqueue(paths: newlyUploadedPaths)
                }
            }
            throw error
        }
    }
}

private extension ProfileAvatarEdit {
    var requiresOldPathCleanup: Bool {
        switch self {
        case .unchanged:
            return false
        case .replace, .remove:
            return true
        }
    }
}
