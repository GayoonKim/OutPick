//
//  ProfileCompositionRoot.swift
//  OutPick
//

import UIKit

enum ProfileCompositionRoot {

    @MainActor
    static func makeProfileSetup(
        initialNickname: String,
        checkNicknameAvailabilityUseCase: CheckNicknameAvailabilityUseCase,
        onNext: @escaping (String) -> Void
    ) -> UIViewController {
        let vm = ProfileSetupViewModel(
            initialNickname: initialNickname,
            checkNicknameAvailabilityUseCase: checkNicknameAvailabilityUseCase,
            onNext: onNext
        )
        let vc = ProfileSetupViewController(viewModel: vm)
        vc.view.backgroundColor = OutPickTheme.ColorToken.backgroundBase
        return vc
    }

    @MainActor
    static func makeAvatarSetup(
        initialAvatar: OnboardingAvatarDraft?,
        onAvatarChanged: @escaping (OnboardingAvatarDraft?) -> Void,
        onBack: @escaping () -> Void,
        onNext: @escaping (OnboardingAvatarDraft?) -> Void
    ) -> UIViewController {
        let vm = AvatarSetupViewModel(
            initialAvatar: initialAvatar,
            onAvatarChanged: onAvatarChanged,
            onBack: onBack,
            onNext: onNext
        )
        let vc = AvatarSetupViewController(viewModel: vm)
        vc.view.backgroundColor = OutPickTheme.ColorToken.backgroundBase
        return vc
    }

    @MainActor
    static func makeStyleMoodOnboarding(
        userID: String,
        draft: OnboardingDraft,
        moodRepository: StyleMoodRepositoryProtocol,
        completeOnboardingUseCase: CompleteOnboardingUseCase,
        onBack: @escaping () -> Void,
        onCompleted: @escaping (CompleteOnboardingOutcome) -> Void
    ) -> UIViewController {
        let vm = StyleMoodOnboardingViewModel(
            userID: userID,
            draft: draft,
            moodRepository: moodRepository,
            completeOnboardingUseCase: completeOnboardingUseCase,
            onBack: onBack,
            onCompleted: onCompleted
        )
        let vc = StyleMoodOnboardingViewController(viewModel: vm)
        vc.view.backgroundColor = OutPickTheme.ColorToken.backgroundBase
        return vc
    }
}
