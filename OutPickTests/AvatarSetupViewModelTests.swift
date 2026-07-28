import Foundation
import Testing
import UIKit
@testable import OutPick

@MainActor
struct AvatarSetupViewModelTests {
    @Test
    func pickedImageEnablesNextAndIsForwarded() {
        var changedAvatar: OnboardingAvatarDraft?
        var nextAvatar: OnboardingAvatarDraft?
        let viewModel = makeViewModel(
            onAvatarChanged: { changedAvatar = $0 },
            onNext: { nextAvatar = $0 }
        )

        viewModel.setPickedImage(
            thumbnail: UIImage(),
            originalFileURL: URL(fileURLWithPath: "/tmp/avatar.jpg"),
            sha256: "avatar-sha"
        )
        viewModel.nextTapped()

        #expect(viewModel.state.isNextEnabled)
        #expect(changedAvatar?.sha256 == "avatar-sha")
        #expect(nextAvatar?.sha256 == "avatar-sha")
    }

    @Test
    func skipClearsExistingAvatarAndContinuesWithoutIt() {
        let initial = OnboardingAvatarDraft(
            thumbnail: UIImage(),
            originalFileURL: URL(fileURLWithPath: "/tmp/avatar.jpg"),
            sha256: "avatar-sha"
        )
        var didClear = false
        var didContinueWithoutAvatar = false
        let viewModel = makeViewModel(
            initialAvatar: initial,
            onAvatarChanged: { didClear = $0 == nil },
            onNext: { didContinueWithoutAvatar = $0 == nil }
        )

        viewModel.skipTapped()

        #expect(viewModel.state.selectedThumbnail == nil)
        #expect(viewModel.state.isNextEnabled == false)
        #expect(didClear)
        #expect(didContinueWithoutAvatar)
    }

    private func makeViewModel(
        initialAvatar: OnboardingAvatarDraft? = nil,
        onAvatarChanged: @escaping (OnboardingAvatarDraft?) -> Void = { _ in },
        onNext: @escaping (OnboardingAvatarDraft?) -> Void = { _ in }
    ) -> AvatarSetupViewModel {
        AvatarSetupViewModel(
            initialAvatar: initialAvatar,
            onAvatarChanged: onAvatarChanged,
            onBack: {},
            onNext: onNext
        )
    }
}
