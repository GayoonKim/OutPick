import Foundation
import UIKit

@MainActor
final class ProfileEditViewModel {
    struct State {
        var nickname: String
        var remoteAvatarPath: String?
        var selectedThumbnail: UIImage?
        var isAvatarRemoved = false
        var isSaving = false
        var isSaveEnabled = false
        var errorMessage: String?
    }

    private(set) var state: State {
        didSet { onStateChanged?(state) }
    }

    var onStateChanged: ((State) -> Void)?

    private let currentProfile: UserPublicProfile
    private let updateUseCase: UpdatePublicProfileUseCase
    private let onSaved: (UpdatePublicProfileOutcome) -> Void
    private var avatarEdit: ProfileAvatarEdit = .unchanged

    init(
        currentProfile: UserPublicProfile,
        updateUseCase: UpdatePublicProfileUseCase,
        onSaved: @escaping (UpdatePublicProfileOutcome) -> Void
    ) {
        self.currentProfile = currentProfile
        self.updateUseCase = updateUseCase
        self.onSaved = onSaved
        state = State(
            nickname: currentProfile.nickname,
            remoteAvatarPath: currentProfile.avatarThumbPath ?? currentProfile.avatarOriginalPath
        )
        recompute()
    }

    func setNickname(_ nickname: String) {
        state.nickname = nickname
        state.errorMessage = nil
        recompute()
    }

    func setPickedImage(
        thumbnail: UIImage,
        originalFileURL: URL,
        sha256: String
    ) {
        avatarEdit = .replace(
            OnboardingAvatarDraft(
                thumbnail: thumbnail,
                originalFileURL: originalFileURL,
                sha256: sha256
            )
        )
        state.selectedThumbnail = thumbnail
        state.isAvatarRemoved = false
        state.errorMessage = nil
        recompute()
    }

    func removeAvatar() {
        avatarEdit = .remove
        state.selectedThumbnail = nil
        state.isAvatarRemoved = true
        state.errorMessage = nil
        recompute()
    }

    func saveTapped() {
        Task { await save() }
    }

    func save() async {
        guard state.isSaveEnabled, state.isSaving == false else { return }
        state.isSaving = true
        state.errorMessage = nil
        recompute()
        do {
            let outcome = try await updateUseCase.execute(
                currentProfile: currentProfile,
                nickname: state.nickname,
                avatarEdit: avatarEdit
            )
            state.isSaving = false
            recompute()
            onSaved(outcome)
        } catch UpdatePublicProfileError.nicknameUnavailable {
            state.isSaving = false
            state.errorMessage = "이미 사용 중인 닉네임이에요"
            recompute()
        } catch {
            state.isSaving = false
            state.errorMessage = "프로필을 저장하지 못했어요"
            recompute()
        }
    }

    private func recompute() {
        let nickname = state.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let isNicknameValid = (2...20).contains(nickname.count)
        let hasNicknameChange = nickname != currentProfile.nickname
        let hasAvatarChange: Bool
        switch avatarEdit {
        case .unchanged:
            hasAvatarChange = false
        case .replace, .remove:
            hasAvatarChange = true
        }
        state.isSaveEnabled = isNicknameValid &&
            (hasNicknameChange || hasAvatarChange) &&
            state.isSaving == false
    }
}
