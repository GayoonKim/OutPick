//
//  DefaultSocialAuthRepository.swift
//  OutPick
//
//  Created by 김가윤 on 2/3/26.
//

import UIKit
import FirebaseAuth
import GoogleSignIn

import KakaoSDKCommon
import KakaoSDKAuth
import KakaoSDKUser

final class DefaultSocialAuthRepository: SocialAuthRepositoryProtocol {

    // MARK: - Launch restore (이메일 채우기)

    func restoreGoogleEmailIfLoggedIn() async -> String? {
        guard let currentUser = Auth.auth().currentUser else { return nil }

        let ok: Bool = await withCheckedContinuation { cont in
            currentUser.getIDTokenForcingRefresh(true) { _, error in
                if let error {
                    print("Google 토큰 갱신 실패: \(error)")
                    cont.resume(returning: false)
                } else {
                    cont.resume(returning: true)
                }
            }
        }
        guard ok else { return nil }

        let email = Auth.auth().currentUser?.email
        return (email?.isEmpty == false) ? email : nil
    }

    func restoreKakaoEmailIfLoggedIn() async -> String? {
        guard AuthApi.hasToken() else { return nil }

        // 토큰 유효성 확인
        let valid: Bool = await withCheckedContinuation { cont in
            UserApi.shared.accessTokenInfo { _, error in
                if let error {
                    // invalid token이면 로그인 해제 취급
                    if let sdkError = error as? SdkError, sdkError.isInvalidTokenError() == true {
                        cont.resume(returning: false)
                        return
                    }
                    print("Kakao 토큰 확인 오류: \(error)")
                    cont.resume(returning: false)
                    return
                }
                cont.resume(returning: true)
            }
        }
        guard valid else { return nil }

        // 이메일 가져오기
        let email: String? = await withCheckedContinuation { cont in
            UserApi.shared.me { user, error in
                if let error {
                    print("Kakao me 실패: \(error)")
                    cont.resume(returning: nil)
                    return
                }
                let email = user?.kakaoAccount?.email
                cont.resume(returning: (email?.isEmpty == false) ? email : nil)
            }
        }
        return email
    }

    // MARK: - Sign-in (UI)

    @MainActor
    func signInWithGoogle(presenter: UIViewController) async throws -> String {
        let user: GIDGoogleUser = try await withCheckedThrowingContinuation { cont in
            GIDSignIn.sharedInstance.signIn(withPresenting: presenter) { result, error in
                if let error { cont.resume(throwing: error); return }
                guard let user = result?.user else {
                    cont.resume(throwing: LoginAuthError.missingIDToken)
                    return
                }
                cont.resume(returning: user)
            }
        }

        guard let idToken = user.idToken?.tokenString else { throw LoginAuthError.missingIDToken }
        let accessToken = user.accessToken.tokenString
        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)

        _ = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            Auth.auth().signIn(with: credential) { _, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume(returning: ()) }
            }
        }

        guard let email = Auth.auth().currentUser?.email, !email.isEmpty else {
            throw LoginAuthError.missingEmail
        }
        return email
    }

    @MainActor
    func signInWithKakao(presenter: UIViewController) async throws -> String {
        // Talk 가능하면 Talk, 아니면 Account
        if UserApi.isKakaoTalkLoginAvailable() {
            _ = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                UserApi.shared.loginWithKakaoTalk { _, error in
                    if let error { cont.resume(throwing: error) }
                    else { cont.resume(returning: ()) }
                }
            }
        } else {
            _ = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                UserApi.shared.loginWithKakaoAccount { _, error in
                    if let error { cont.resume(throwing: error) }
                    else { cont.resume(returning: ()) }
                }
            }
        }

        let email: String = try await withCheckedThrowingContinuation { cont in
            UserApi.shared.me { user, error in
                if let error { cont.resume(throwing: error); return }
                guard let email = user?.kakaoAccount?.email, !email.isEmpty else {
                    cont.resume(throwing: LoginAuthError.missingEmail)
                    return
                }
                cont.resume(returning: email)
            }
        }
        return email
    }
}
