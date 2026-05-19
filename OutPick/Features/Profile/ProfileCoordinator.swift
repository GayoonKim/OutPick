//
//  ProfileCoordinator.swift
//  OutPick
//

import UIKit

/// 프로필 플로우(1단계 -> 2단계 -> 완료)를 전담하는 Coordinator
final class ProfileCoordinator {

    private let navigationController: UINavigationController
    private let repository: UserProfileRepositoryProtocol

    /// 프로필 완료 시 호출 (메인탭 전환은 AppCoordinator가 담당)
    private let onCompleted: (UserProfile) -> Void

    init(
        navigationController: UINavigationController,
        repository: UserProfileRepositoryProtocol,
        onCompleted: @escaping (UserProfile) -> Void
    ) {
        self.navigationController = navigationController
        self.repository = repository
        self.onCompleted = onCompleted
    }

    @MainActor
    func start() {
        let vc = ProfileCompositionRoot.makeFirst(
            repository: repository,
            onNext: { [weak self] draft in
                guard let self else { return }
                // 다음 버튼 탭 → 2단계 화면 push
                Task { @MainActor in
                    self.showSecond(draft: draft)
                }
            }
        )
        navigationController.setViewControllers([vc], animated: false)
    }

    @MainActor
    private func showSecond(draft: UserProfileDraft) {
        let vc = ProfileCompositionRoot.makeSecond(
            repository: repository,
            draft: draft,
            onBack: { [weak self] in
                guard let self else { return }
                self.navigationController.popViewController(animated: true)
            },
            onCompleted: { [weak self] profile in
                guard let self else { return }
                self.onCompleted(profile)
            }
        )
        navigationController.pushViewController(vc, animated: true)
    }
}
