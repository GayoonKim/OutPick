//
//  UserProfileDetailCoordinator.swift
//  OutPick
//

import UIKit

@MainActor
final class UserProfileDetailCoordinator {
    private weak var presentingViewController: UIViewController?
    private weak var presentedViewController: UIViewController?

    private let provider: ChatManagerProviding
    private let repositories: FirebaseRepositoryProviding
    private let onFinish: () -> Void

    init(
        presentingViewController: UIViewController,
        provider: ChatManagerProviding,
        repositories: FirebaseRepositoryProviding,
        onFinish: @escaping () -> Void
    ) {
        self.presentingViewController = presentingViewController
        self.provider = provider
        self.repositories = repositories
        self.onFinish = onFinish
    }

    func start(email: String, nickname: String, avatarPath: String?) {
        guard presentedViewController == nil,
              let presentingViewController else { return }

        let viewController = UserProfileDetailCompositionRoot.makeDetail(
            email: email,
            seedNickname: nickname,
            seedAvatarPath: avatarPath,
            provider: provider,
            repositories: repositories,
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
