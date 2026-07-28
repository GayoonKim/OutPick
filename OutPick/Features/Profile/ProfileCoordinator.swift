//
//  ProfileCoordinator.swift
//  OutPick
//

import UIKit

/// 프로필과 관심 무드 온보딩 흐름을 전담하는 Coordinator
final class ProfileCoordinator: NSObject {

    private let navigationController: UINavigationController
    private let userID: String
    private let moodRepository: StyleMoodRepositoryProtocol
    private let checkNicknameAvailabilityUseCase: CheckNicknameAvailabilityUseCase
    private let completeOnboardingUseCase: CompleteOnboardingUseCase
    private var nickname = ""
    private var avatar: OnboardingAvatarDraft?

    /// 프로필 완료 시 호출 (메인탭 전환은 AppCoordinator가 담당)
    private let onCompleted: (CompleteOnboardingOutcome) -> Void

    init(
        navigationController: UINavigationController,
        userID: String,
        moodRepository: StyleMoodRepositoryProtocol,
        checkNicknameAvailabilityUseCase: CheckNicknameAvailabilityUseCase,
        completeOnboardingUseCase: CompleteOnboardingUseCase,
        onCompleted: @escaping (CompleteOnboardingOutcome) -> Void
    ) {
        self.navigationController = navigationController
        self.userID = userID
        self.moodRepository = moodRepository
        self.checkNicknameAvailabilityUseCase = checkNicknameAvailabilityUseCase
        self.completeOnboardingUseCase = completeOnboardingUseCase
        self.onCompleted = onCompleted
        super.init()
    }

    @MainActor
    func start() {
        navigationController.delegate = self
        let vc = ProfileCompositionRoot.makeProfileSetup(
            initialNickname: nickname,
            checkNicknameAvailabilityUseCase: checkNicknameAvailabilityUseCase,
            onNext: { [weak self] nickname in
                guard let self else { return }
                self.nickname = nickname
                self.showAvatarSetup()
            }
        )
        navigationController.setViewControllers([vc], animated: false)
    }

    @MainActor
    private func showAvatarSetup() {
        let vc = ProfileCompositionRoot.makeAvatarSetup(
            initialAvatar: avatar,
            onAvatarChanged: { [weak self] avatar in
                self?.avatar = avatar
            },
            onBack: { [weak self] in
                self?.navigationController.popViewController(animated: true)
            },
            onNext: { [weak self] avatar in
                guard let self else { return }
                self.avatar = avatar
                self.showStyleMoodOnboarding()
            }
        )
        navigationController.pushViewController(vc, animated: true)
    }

    @MainActor
    private func showStyleMoodOnboarding() {
        let draft = OnboardingDraft(nickname: nickname, avatar: avatar)
        let vc = ProfileCompositionRoot.makeStyleMoodOnboarding(
            userID: userID,
            draft: draft,
            moodRepository: moodRepository,
            completeOnboardingUseCase: completeOnboardingUseCase,
            onBack: { [weak self] in
                guard let self else { return }
                self.navigationController.popViewController(animated: true)
            },
            onCompleted: { [weak self] outcome in
                guard let self else { return }
                self.onCompleted(outcome)
            }
        )
        navigationController.pushViewController(vc, animated: true)
    }
}

extension ProfileCoordinator: UINavigationControllerDelegate {
    func navigationController(
        _ navigationController: UINavigationController,
        animationControllerFor operation: UINavigationController.Operation,
        from fromVC: UIViewController,
        to toVC: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        guard operation == .push || operation == .pop else { return nil }
        return OnboardingTransitionAnimator(operation: operation)
    }
}
