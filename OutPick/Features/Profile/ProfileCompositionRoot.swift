//
//  ProfileCompositionRoot.swift
//  OutPick
//

import UIKit

enum ProfileCompositionRoot {

    @MainActor
    static func makeFirst(
        repository: UserProfileRepositoryProtocol,
        onNext: @escaping (UserProfileDraft) -> Void
    ) -> UIViewController {
        let vm = FirstProfileViewModel(onNext: onNext)
        let vc = FirstProfileViewController(viewModel: vm)
        vc.view.backgroundColor = .systemBackground
        return vc
    }

    @MainActor
    static func makeSecond(
        repository: UserProfileRepositoryProtocol,
        draft: UserProfileDraft,
        onBack: @escaping () -> Void,
        onCompleted: @escaping (UserProfile) -> Void
    ) -> UIViewController {

        let vm = SecondProfileViewModel(
            repository: repository,
            draft: draft,
            onBack: onBack,
            onCompleted: onCompleted
        )
        let vc = SecondProfileViewController(viewModel: vm)
        vc.view.backgroundColor = .systemBackground
        return vc
    }
}
