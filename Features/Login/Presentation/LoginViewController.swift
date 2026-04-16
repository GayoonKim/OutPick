//
//  LoginViewController.swift
//  OutPick
//
//  Created by 김가윤 on 8/1/24.
//

import UIKit

@MainActor
final class LoginViewController: UIViewController {

    private let viewModel: LoginViewModel

    private let googleButton = UIButton(type: .system)
    private let kakaoButton  = UIButton(type: .system)
    private var pendingErrorMessage: String?

    init(viewModel: LoginViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("LoginViewController는 스토리보드 없이 생성해야 합니다.")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureUI()
        bind()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showPendingErrorIfNeeded()
    }

    private func configureUI() {
        if let img = UIImage(named: "ios_light_sq_SI") {
            googleButton.setImage(img.withRenderingMode(.alwaysOriginal), for: .normal)
            googleButton.imageView?.contentMode = .scaleAspectFit
        } else {
            googleButton.setTitle("Google로 로그인", for: .normal)
        }

        if let img = UIImage(named: "kakao_login_medium_narrow") {
            kakaoButton.setImage(img.withRenderingMode(.alwaysOriginal), for: .normal)
            kakaoButton.imageView?.contentMode = .scaleAspectFit
        } else {
            kakaoButton.setTitle("카카오로 로그인", for: .normal)
        }

        googleButton.heightAnchor.constraint(equalToConstant: 48).isActive = true
        kakaoButton.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let stack = UIStackView(arrangedSubviews: [googleButton, kakaoButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])

        googleButton.addTarget(self, action: #selector(googleTapped), for: .touchUpInside)
        kakaoButton.addTarget(self, action: #selector(kakaoTapped), for: .touchUpInside)
    }

    private func bind() {
        viewModel.onStateChange = { [weak self] state in
            guard let self else { return }
            switch state {
            case .idle:
                self.setEnabled(true)
            case .loading:
                self.setEnabled(false)
            case .error(let msg):
                self.setEnabled(true)
                self.presentErrorWhenPossible(msg)
            }
        }
    }

    private func setEnabled(_ enabled: Bool) {
        googleButton.isEnabled = enabled
        kakaoButton.isEnabled  = enabled
        googleButton.alpha = enabled ? 1 : 0.6
        kakaoButton.alpha  = enabled ? 1 : 0.6
    }

    private func presentErrorWhenPossible(_ message: String) {
        guard isViewLoaded, view.window != nil else {
            pendingErrorMessage = message
            return
        }
        AlertManager.showAlertNoHandler(title: "로그인 실패", message: message, viewController: self)
    }

    private func showPendingErrorIfNeeded() {
        guard let pendingErrorMessage else { return }
        self.pendingErrorMessage = nil
        presentErrorWhenPossible(pendingErrorMessage)
    }

    @objc private func googleTapped() { viewModel.tapGoogle(presenter: self) }
    @objc private func kakaoTapped() { viewModel.tapKakao(presenter: self) }
}
