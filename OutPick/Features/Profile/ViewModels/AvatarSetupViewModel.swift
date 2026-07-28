import Foundation
import UIKit

@MainActor
final class AvatarSetupViewModel {
    struct State {
        var selectedThumbnail: UIImage?
        var isNextEnabled = false
    }

    private(set) var state: State {
        didSet { onStateChanged?(state) }
    }

    var onStateChanged: ((State) -> Void)?

    private var avatarDraft: OnboardingAvatarDraft?
    private let onAvatarChanged: (OnboardingAvatarDraft?) -> Void
    private let onBack: () -> Void
    private let onNext: (OnboardingAvatarDraft?) -> Void

    init(
        initialAvatar: OnboardingAvatarDraft?,
        onAvatarChanged: @escaping (OnboardingAvatarDraft?) -> Void,
        onBack: @escaping () -> Void,
        onNext: @escaping (OnboardingAvatarDraft?) -> Void
    ) {
        avatarDraft = initialAvatar
        state = State(
            selectedThumbnail: initialAvatar?.thumbnail,
            isNextEnabled: initialAvatar != nil
        )
        self.onAvatarChanged = onAvatarChanged
        self.onBack = onBack
        self.onNext = onNext
    }

    func setPickedImage(
        thumbnail: UIImage,
        originalFileURL: URL,
        sha256: String
    ) {
        let draft = OnboardingAvatarDraft(
            thumbnail: thumbnail,
            originalFileURL: originalFileURL,
            sha256: sha256
        )
        avatarDraft = draft
        state.selectedThumbnail = thumbnail
        recompute()
        onAvatarChanged(draft)
    }

    func clearImage() {
        avatarDraft = nil
        state.selectedThumbnail = nil
        recompute()
        onAvatarChanged(nil)
    }

    func backTapped() {
        onBack()
    }

    func nextTapped() {
        guard avatarDraft != nil else { return }
        onNext(avatarDraft)
    }

    func skipTapped() {
        avatarDraft = nil
        state.selectedThumbnail = nil
        onAvatarChanged(nil)
        recompute()
        onNext(nil)
    }

    private func recompute() {
        state.isNextEnabled = avatarDraft != nil
    }
}
