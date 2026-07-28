//
//  UserProfileDetailCoordinator.swift
//  OutPick
//

import UIKit

@MainActor
final class UserProfileDetailCoordinator {
    private weak var presentingViewController: UIViewController?
    private weak var presentedViewController: UIViewController?

    private let avatarImageManager: AvatarImageManaging
    private let currentUserProvider: CurrentUserProviding
    private let publicProfileRepository: UserPublicProfileRepositoryProtocol
    private let photoLibrarySaver: PhotoLibrarySaving
    private let onFinish: () -> Void

    init(
        presentingViewController: UIViewController,
        avatarImageManager: AvatarImageManaging,
        currentUserProvider: CurrentUserProviding,
        publicProfileRepository: UserPublicProfileRepositoryProtocol,
        photoLibrarySaver: PhotoLibrarySaving,
        onFinish: @escaping () -> Void
    ) {
        self.presentingViewController = presentingViewController
        self.avatarImageManager = avatarImageManager
        self.currentUserProvider = currentUserProvider
        self.publicProfileRepository = publicProfileRepository
        self.photoLibrarySaver = photoLibrarySaver
        self.onFinish = onFinish
    }

    func start(userID: String, nickname: String, avatarPath: String?) {
        guard presentedViewController == nil,
              let presentingViewController else { return }

        let viewController = UserProfileDetailCompositionRoot.makeDetail(
            userID: userID,
            seedNickname: nickname,
            seedAvatarPath: avatarPath,
            avatarImageManager: avatarImageManager,
            currentUserProvider: currentUserProvider,
            publicProfileRepository: publicProfileRepository,
            photoLibrarySaver: photoLibrarySaver,
            onBack: { [weak self] in
                self?.dismiss()
            }
        )
        viewController.modalPresentationStyle = .overFullScreen
        presentedViewController = viewController
        ChatModalTransitionManager.present(viewController, from: presentingViewController)
    }

    private func dismiss() {
        guard let presentedViewController else {
            onFinish()
            return
        }

        self.presentedViewController = nil
        ChatModalTransitionManager.dismiss(from: presentedViewController)
        onFinish()
    }
}
