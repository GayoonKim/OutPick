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

enum GoogleAccountDeletionReauthenticationMode: Equatable {
    case reauthenticate
    case signIn
}

enum GoogleAccountDeletionReauthenticationPolicy {
    static func mode(
        currentFirebaseUserID: String?,
        expectedFirebaseUserID: String
    ) throws -> GoogleAccountDeletionReauthenticationMode {
        guard let currentFirebaseUserID else {
            return .signIn
        }
        guard currentFirebaseUserID == expectedFirebaseUserID else {
            throw AccountDeletionClientError.identityMismatch
        }
        return .reauthenticate
    }
}

final class DefaultSocialAuthRepository:
    SocialAuthRepositoryProtocol,
    AccountDeletionReauthenticating {
    private let kakaoAuthBridge: any KakaoAuthBridgeCalling

    init(kakaoAuthBridge: any KakaoAuthBridgeCalling) {
        self.kakaoAuthBridge = kakaoAuthBridge
    }

    static func live(
        transport: any CloudFunctionsTransporting = FirebaseCloudFunctionsTransport()
    ) -> DefaultSocialAuthRepository {
        DefaultSocialAuthRepository(
            kakaoAuthBridge: CloudFunctionsKakaoAuthBridgeClient(transport: transport)
        )
    }

    // MARK: - Launch restore

    func restoreGoogleUserIfLoggedIn() async -> AuthenticatedUser? {
        guard let currentUser = Auth.auth().currentUser else { return nil }
        guard currentUser.providerData.contains(where: { $0.providerID == "google.com" }) else {
            return nil
        }

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

        let uid = currentUser.uid
        guard !uid.isEmpty else { return nil }

        return makeGoogleAuthenticatedUser(from: currentUser)
    }

    func restoreKakaoUserIfLoggedIn() async -> AuthenticatedUser? {
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

        let kakaoUser: KakaoSDKUser.User? = await withCheckedContinuation { (cont: CheckedContinuation<KakaoSDKUser.User?, Never>) in
            UserApi.shared.me { user, error in
                if let error {
                    print("Kakao me 실패: \(error)")
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: user)
            }
        }
        guard let authenticatedUser = makeKakaoAuthenticatedUser(from: kakaoUser) else { return nil }
        guard let firebaseUser = Auth.auth().currentUser,
              firebaseUser.uid == authenticatedUser.identityKey else {
            return nil
        }

        let firebaseTokenValid: Bool = await withCheckedContinuation { cont in
            firebaseUser.getIDTokenForcingRefresh(true) { _, error in
                if let error {
                    print("Kakao Firebase 토큰 갱신 실패: \(error)")
                    cont.resume(returning: false)
                } else {
                    cont.resume(returning: true)
                }
            }
        }

        return firebaseTokenValid ? authenticatedUser : nil
    }

    // MARK: - Sign-in (UI)

    @MainActor
    func signInWithGoogle(presenter: UIViewController) async throws -> AuthenticatedUser {
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

        let authUser = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<FirebaseAuth.User, Error>) in
            Auth.auth().signIn(with: credential) { result, error in
                if let error { cont.resume(throwing: error) }
                else if let user = result?.user { cont.resume(returning: user) }
                else { cont.resume(throwing: LoginAuthError.missingIDToken) }
            }
        }

        return makeGoogleAuthenticatedUser(from: authUser)
    }

    @MainActor
    func signInWithKakao(presenter: UIViewController) async throws -> AuthenticatedUser {
        // Talk 가능하면 Talk, 아니면 Account
        let accessToken: String
        if UserApi.isKakaoTalkLoginAvailable() {
            accessToken = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                UserApi.shared.loginWithKakaoTalk { token, error in
                    if let error { cont.resume(throwing: error) }
                    else if let accessToken = token?.accessToken, !accessToken.isEmpty {
                        cont.resume(returning: accessToken)
                    } else {
                        cont.resume(throwing: LoginAuthError.missingIDToken)
                    }
                }
            }
        } else {
            accessToken = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                UserApi.shared.loginWithKakaoAccount { token, error in
                    if let error { cont.resume(throwing: error) }
                    else if let accessToken = token?.accessToken, !accessToken.isEmpty {
                        cont.resume(returning: accessToken)
                    } else {
                        cont.resume(throwing: LoginAuthError.missingIDToken)
                    }
                }
            }
        }

        let kakaoUser: KakaoSDKUser.User = try await withCheckedThrowingContinuation { cont in
            UserApi.shared.me { user, error in
                if let error { cont.resume(throwing: error); return }
                guard let user else {
                    cont.resume(throwing: LoginAuthError.missingIDToken)
                    return
                }
                cont.resume(returning: user)
            }
        }

        return try await signInToFirebaseWithKakao(
            accessToken: accessToken,
            kakaoUser: kakaoUser
        )
    }

    @MainActor
    func reauthenticateForAccountDeletion(
        expectedUser: AuthenticatedUser,
        presenter: UIViewController
    ) async throws {
        switch expectedUser.provider {
        case .google:
            try await reauthenticateGoogle(
                expectedUser: expectedUser,
                presenter: presenter
            )
        case .kakao:
            try await reauthenticateKakao(expectedUser: expectedUser)
        }
    }

    @MainActor
    func authenticatePendingAccount(
        provider: AuthProvider,
        presenter: UIViewController
    ) async throws -> AuthenticatedUser {
        switch provider {
        case .google:
            return try await signInWithGoogle(presenter: presenter)
        case .kakao:
            return try await signInWithKakao(presenter: presenter)
        }
    }

    @MainActor
    private func reauthenticateGoogle(
        expectedUser: AuthenticatedUser,
        presenter: UIViewController
    ) async throws {
        let currentUser = Auth.auth().currentUser
        let mode = try GoogleAccountDeletionReauthenticationPolicy.mode(
            currentFirebaseUserID: currentUser?.uid,
            expectedFirebaseUserID: expectedUser.identityKey
        )

        let googleUser: GIDGoogleUser = try await withCheckedThrowingContinuation { cont in
            GIDSignIn.sharedInstance.signIn(withPresenting: presenter) { result, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                guard let user = result?.user else {
                    cont.resume(throwing: LoginAuthError.missingIDToken)
                    return
                }
                cont.resume(returning: user)
            }
        }
        guard let idToken = googleUser.idToken?.tokenString else {
            throw LoginAuthError.missingIDToken
        }
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: googleUser.accessToken.tokenString
        )
        let result: AuthDataResult
        switch mode {
        case .reauthenticate:
            guard let currentUser else {
                throw AccountDeletionClientError.missingAuthenticatedUser
            }
            result = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<AuthDataResult, Error>) in
                currentUser.reauthenticate(with: credential) { result, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let result {
                        continuation.resume(returning: result)
                    } else {
                        continuation.resume(throwing: LoginAuthError.missingIDToken)
                    }
                }
            }
        case .signIn:
            result = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<AuthDataResult, Error>) in
                Auth.auth().signIn(with: credential) { result, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let result {
                        continuation.resume(returning: result)
                    } else {
                        continuation.resume(throwing: LoginAuthError.missingIDToken)
                    }
                }
            }
        }

        let googleProviderUserID = result.user.providerData
            .first(where: { $0.providerID == "google.com" })?
            .uid
        guard result.user.uid == expectedUser.identityKey,
              googleProviderUserID == expectedUser.providerUserID else {
            throw AccountDeletionClientError.identityMismatch
        }
        try await refreshIDToken(for: result.user)
    }

    @MainActor
    private func reauthenticateKakao(
        expectedUser: AuthenticatedUser
    ) async throws {
        let accessToken: String = try await withCheckedThrowingContinuation { cont in
            UserApi.shared.loginWithKakaoAccount(prompts: [.Login]) { token, error in
                if let error {
                    cont.resume(throwing: error)
                } else if let accessToken = token?.accessToken, !accessToken.isEmpty {
                    cont.resume(returning: accessToken)
                } else {
                    cont.resume(throwing: LoginAuthError.missingIDToken)
                }
            }
        }
        let kakaoUser: KakaoSDKUser.User = try await withCheckedThrowingContinuation { cont in
            UserApi.shared.me { user, error in
                if let error {
                    cont.resume(throwing: error)
                } else if let user {
                    cont.resume(returning: user)
                } else {
                    cont.resume(throwing: LoginAuthError.missingIDToken)
                }
            }
        }
        guard let candidate = makeKakaoAuthenticatedUser(from: kakaoUser),
              candidate.provider == expectedUser.provider else {
            throw AccountDeletionClientError.providerMismatch
        }
        guard candidate.identityKey == expectedUser.identityKey,
              candidate.providerUserID == expectedUser.providerUserID else {
            throw AccountDeletionClientError.identityMismatch
        }

        let authenticated = try await signInToFirebaseWithKakao(
            accessToken: accessToken,
            kakaoUser: kakaoUser
        )
        guard authenticated.identityKey == expectedUser.identityKey else {
            throw AccountDeletionClientError.identityMismatch
        }
        guard let currentUser = Auth.auth().currentUser else {
            throw AccountDeletionClientError.missingAuthenticatedUser
        }
        try await refreshIDToken(for: currentUser)
    }

    private func makeGoogleAuthenticatedUser(from user: FirebaseAuth.User) -> AuthenticatedUser {
        let googleProviderID = user.providerData
            .first(where: { $0.providerID == "google.com" })?
            .uid

        return AuthenticatedUser(
            identityKey: user.uid,
            provider: .google,
            providerUserID: googleProviderID ?? user.uid,
            email: user.email
        )
    }

    private func refreshIDToken(for user: FirebaseAuth.User) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            user.getIDTokenForcingRefresh(true) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func makeKakaoAuthenticatedUser(from user: KakaoSDKUser.User?) -> AuthenticatedUser? {
        guard let kakaoID = user?.id else { return nil }
        let providerUserID = String(kakaoID)

        return AuthenticatedUser(
            identityKey: "kakao:\(providerUserID)",
            provider: .kakao,
            providerUserID: providerUserID,
            email: user?.kakaoAccount?.email
        )
    }

    @MainActor
    private func signInToFirebaseWithKakao(
        accessToken: String,
        kakaoUser: KakaoSDKUser.User
    ) async throws -> AuthenticatedUser {
        let bridge = try await kakaoAuthBridge.exchangeKakaoToken(
            accessToken: accessToken
        )

        let firebaseUser = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<FirebaseAuth.User, Error>) in
            Auth.auth().signIn(withCustomToken: bridge.firebaseCustomToken) { result, error in
                if let error {
                    cont.resume(throwing: error)
                } else if let user = result?.user {
                    cont.resume(returning: user)
                } else {
                    cont.resume(throwing: LoginAuthError.missingIDToken)
                }
            }
        }

        guard firebaseUser.uid == bridge.identityKey else {
            throw LoginAuthError.missingIDToken
        }

        return AuthenticatedUser(
            identityKey: bridge.identityKey,
            provider: .kakao,
            providerUserID: bridge.providerUserID,
            email: bridge.email ?? kakaoUser.kakaoAccount?.email
        )
    }
}
