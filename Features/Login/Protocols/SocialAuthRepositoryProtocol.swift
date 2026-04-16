//
//  SocialAuthRepositoryProtocol.swift
//  OutPick
//
//  Created by 김가윤 on 2/3/26.
//

import UIKit

protocol SocialAuthRepositoryProtocol {
    // 로그인 UI 플로우(버튼 탭)용
    func signInWithGoogle(presenter: UIViewController) async throws -> AuthenticatedUser
    func signInWithKakao(presenter: UIViewController) async throws -> AuthenticatedUser

    // Launch 자동로그인 체크용
    func restoreGoogleUserIfLoggedIn() async -> AuthenticatedUser?
    func restoreKakaoUserIfLoggedIn() async -> AuthenticatedUser?
}
