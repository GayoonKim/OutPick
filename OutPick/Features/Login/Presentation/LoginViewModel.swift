//
//  LoginViewModel.swift
//  OutPick
//
//  Created by 김가윤 on 2/3/26.
//

import UIKit

final class LoginViewModel {

    enum State: Equatable {
        case idle
        case loading
        case error(String)
    }

    private let authRepository: SocialAuthRepositoryProtocol

    var onLoginSuccess: ((AuthenticatedUser) -> Void)?
    var onStateChange: ((State) -> Void)?

    private var state: State = .idle {
        didSet { onStateChange?(state) }
    }

    init(authRepository: SocialAuthRepositoryProtocol) {
        self.authRepository = authRepository
    }

    func tapGoogle(presenter: UIViewController) {
        state = .loading
        Task {
            do {
                let authenticatedUser = try await authRepository.signInWithGoogle(presenter: presenter)
                await MainActor.run {
                    self.state = .idle
                    self.onLoginSuccess?(authenticatedUser)
                }
            } catch {
                self.logLoginFailure(provider: "Google", error: error)
                await MainActor.run {
                    self.state = .error("로그인에 실패했습니다. \(error.localizedDescription)")
                }
            }
        }
    }

    func tapKakao(presenter: UIViewController) {
        state = .loading
        Task {
            do {
                let authenticatedUser = try await authRepository.signInWithKakao(presenter: presenter)
                await MainActor.run {
                    self.state = .idle
                    self.onLoginSuccess?(authenticatedUser)
                }
            } catch {
                self.logLoginFailure(provider: "Kakao", error: error)
                await MainActor.run {
                    self.state = .error("로그인에 실패했습니다. \(error.localizedDescription)")
                }
            }
        }
    }

    private func logLoginFailure(provider: String, error: Error) {
        let nsError = error as NSError
        print(
            "[LoginViewModel] \(provider) login failed: " +
            "domain=\(nsError.domain), code=\(nsError.code), " +
            "description=\(nsError.localizedDescription), " +
            "userInfo=\(nsError.userInfo)"
        )
    }
}
