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

    var onLoginSuccess: ((String) -> Void)?
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
                let email = try await authRepository.signInWithGoogle(presenter: presenter)
                await MainActor.run {
                    self.state = .idle
                    self.onLoginSuccess?(email)
                }
            } catch {
                await MainActor.run {
                    self.state = .error("로그인에 실패했습니다. 다시 시도해주세요.")
                }
            }
        }
    }

    func tapKakao(presenter: UIViewController) {
        state = .loading
        Task {
            do {
                let email = try await authRepository.signInWithKakao(presenter: presenter)
                await MainActor.run {
                    self.state = .idle
                    self.onLoginSuccess?(email)
                }
            } catch {
                await MainActor.run {
                    self.state = .error("로그인에 실패했습니다. 다시 시도해주세요.")
                }
            }
        }
    }
}
