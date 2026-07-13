//
//  LoginCompositionRoot.swift
//  OutPick
//
//  Created by 김가윤 on 2/3/26.
//

import UIKit

enum LoginCompositionRoot {

    @MainActor
    static func makeViewModel(
        authRepository: SocialAuthRepositoryProtocol
    ) -> LoginViewModel {
        return LoginViewModel(
            authRepository: authRepository
        )
    }

    /// AppCoordinator가 호출할 엔트리
    @MainActor
    static func makeLoginViewController(
        authRepository: SocialAuthRepositoryProtocol,
        onLoginSuccess: @escaping (AuthenticatedUser) -> Void
    ) -> LoginViewController {
        let vm = makeViewModel(authRepository: authRepository)
        vm.onLoginSuccess = onLoginSuccess
        return LoginViewController(viewModel: vm)
    }
}
