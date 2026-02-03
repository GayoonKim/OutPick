//
//  LoginCompositionRoot.swift
//  OutPick
//
//  Created by 김가윤 on 2/3/26.
//

import UIKit

enum LoginCompositionRoot {

    @MainActor
    static func makeViewModel() -> LoginViewModel {
        return LoginViewModel(
            authRepository: DefaultSocialAuthRepository()
        )
    }

    /// AppCoordinator가 호출할 엔트리
    @MainActor
    static func makeLoginViewController(
        onLoginSuccess: @escaping (String) -> Void
    ) -> LoginViewController {
        let vm = makeViewModel()
        vm.onLoginSuccess = onLoginSuccess
        return LoginViewController(viewModel: vm)
    }
}
