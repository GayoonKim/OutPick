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

    private let logoStack = UIStackView()
    private let logoIconContainer = UIView()
    private let logoIconView = UIImageView()
    private let titleLabel = UILabel()
    private let promptLabel = UILabel()
    private let googleButton = UIButton(type: .system)
    private let kakaoButton  = UIButton(type: .system)
    private var pendingErrorMessage: String?
    private var didAnimateLogo = false

    init(viewModel: LoginViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("LoginViewController는 스토리보드 없이 생성해야 합니다.")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = OutPickTheme.ColorToken.backgroundBase
        configureUI()
        bind()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        animateLogoIfNeeded()
        showPendingErrorIfNeeded()
    }

    private func configureUI() {
        logoStack.axis = .vertical
        logoStack.alignment = .center
        logoStack.spacing = 12
        logoStack.alpha = 0
        logoStack.translatesAutoresizingMaskIntoConstraints = false

        logoIconContainer.translatesAutoresizingMaskIntoConstraints = false
        logoIconContainer.backgroundColor = OutPickTheme.ColorToken.surfaceBase
        logoIconContainer.layer.cornerRadius = 26
        logoIconContainer.layer.borderWidth = 1
        logoIconContainer.layer.borderColor = OutPickTheme.ColorToken.borderSubtle.cgColor

        logoIconView.translatesAutoresizingMaskIntoConstraints = false
        logoIconView.image = UIImage(systemName: "tshirt.fill")
        logoIconView.tintColor = OutPickTheme.ColorToken.textPrimary
        logoIconView.contentMode = .scaleAspectFit

        titleLabel.text = "OutPick"
        titleLabel.font = .systemFont(ofSize: 40, weight: .bold)
        titleLabel.textColor = OutPickTheme.ColorToken.textPrimary
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true

        promptLabel.text = "로그인 방식을 선택해 주세요"
        promptLabel.font = .preferredFont(forTextStyle: .subheadline)
        promptLabel.textColor = OutPickTheme.ColorToken.textSecondary
        promptLabel.textAlignment = .center
        promptLabel.numberOfLines = 0
        promptLabel.adjustsFontForContentSizeCategory = true

        if let img = UIImage(named: "ios_light_sq_SI") {
            googleButton.setImage(img.withRenderingMode(.alwaysOriginal), for: .normal)
            googleButton.imageView?.contentMode = .scaleAspectFit
        } else {
            googleButton.setTitle("Google로 로그인", for: .normal)
            googleButton.setTitleColor(OutPickTheme.ColorToken.accent, for: .normal)
        }

        if let img = UIImage(named: "kakao_login_medium_narrow") {
            kakaoButton.setImage(img.withRenderingMode(.alwaysOriginal), for: .normal)
            kakaoButton.imageView?.contentMode = .scaleAspectFit
        } else {
            kakaoButton.setTitle("카카오로 로그인", for: .normal)
            kakaoButton.setTitleColor(OutPickTheme.ColorToken.accent, for: .normal)
        }

        googleButton.heightAnchor.constraint(equalToConstant: 48).isActive = true
        kakaoButton.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let stack = UIStackView(arrangedSubviews: [promptLabel, googleButton, kakaoButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.setCustomSpacing(20, after: promptLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false

        logoIconContainer.addSubview(logoIconView)
        logoStack.addArrangedSubview(logoIconContainer)
        logoStack.addArrangedSubview(titleLabel)
        view.addSubview(logoStack)
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            logoStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            logoStack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -82),
            logoStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            logoStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),

            logoIconContainer.widthAnchor.constraint(equalToConstant: 52),
            logoIconContainer.heightAnchor.constraint(equalToConstant: 52),
            logoIconView.centerXAnchor.constraint(equalTo: logoIconContainer.centerXAnchor),
            logoIconView.centerYAnchor.constraint(equalTo: logoIconContainer.centerYAnchor),
            logoIconView.widthAnchor.constraint(equalToConstant: 27),
            logoIconView.heightAnchor.constraint(equalToConstant: 27),

            stack.topAnchor.constraint(equalTo: logoStack.bottomAnchor, constant: 64),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])

        googleButton.addTarget(self, action: #selector(googleTapped), for: .touchUpInside)
        kakaoButton.addTarget(self, action: #selector(kakaoTapped), for: .touchUpInside)
    }

    private func animateLogoIfNeeded() {
        guard !didAnimateLogo else { return }
        didAnimateLogo = true

        logoStack.alpha = 0
        logoStack.transform = CGAffineTransform(translationX: 0, y: 12).scaledBy(x: 0.96, y: 0.96)

        UIView.animate(
            withDuration: 0.55,
            delay: 0.08,
            usingSpringWithDamping: 0.82,
            initialSpringVelocity: 0.4,
            options: [.curveEaseOut]
        ) {
            self.logoStack.alpha = 1
            self.logoStack.transform = .identity
        }
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
