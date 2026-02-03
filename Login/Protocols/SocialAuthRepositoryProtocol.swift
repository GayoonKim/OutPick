//
//  SocialAuthRepositoryProtocol.swift
//  OutPick
//
//  Created by 김가윤 on 2/3/26.
//

import UIKit

protocol SocialAuthRepositoryProtocol {
    // 로그인 UI 플로우(버튼 탭)용
    func signInWithGoogle(presenter: UIViewController) async throws -> String
    func signInWithKakao(presenter: UIViewController) async throws -> String

    // ✅ Launch 자동로그인 체크용(이메일 채우기)
    func restoreGoogleEmailIfLoggedIn() async -> String?
    func restoreKakaoEmailIfLoggedIn() async -> String?
}
