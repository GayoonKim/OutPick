import UIKit

final class ProfileSetupViewController: UIViewController {
    private let viewModel: ProfileSetupViewModel

    private let headerView = OnboardingEditorialHeaderView()
    private let nicknamePreviewLabel = UILabel()
    private let nicknameField = UITextField()
    private let countLabel = UILabel()
    private let errorLabel = UILabel()
    private let nextButton = UIButton(type: .system)
    private var hasPresentedEntrance = false

    init(viewModel: ProfileSetupViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = OutPickTheme.ColorToken.backgroundBase
        installKeyboardDismissTapGesture()
        configureUI()
        bind()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentEntranceIfNeeded()
    }

    private func configureUI() {
        headerView.configure(
            step: "01 / 03",
            title: "어떤 이름으로\n불러드릴까요",
            subtitle: "OutPick에서 활동할 때 사용할 이름이에요"
        )

        let previewDescriptor = UIFont.systemFont(ofSize: 48, weight: .bold)
            .fontDescriptor
            .withDesign(.serif)
        nicknamePreviewLabel.font = previewDescriptor.map {
            UIFont(descriptor: $0, size: 48)
        } ?? .systemFont(ofSize: 48, weight: .bold)
        nicknamePreviewLabel.textColor = OutPickTheme.ColorToken.textPrimary
        nicknamePreviewLabel.numberOfLines = 2
        nicknamePreviewLabel.text = "YOUR\nNAME"
        nicknamePreviewLabel.alpha = 0.16
        nicknamePreviewLabel.accessibilityElementsHidden = true

        nicknameField.placeholder = "닉네임 (2~20자)"
        nicknameField.backgroundColor = OutPickTheme.ColorToken.surfaceBase
        nicknameField.textColor = OutPickTheme.ColorToken.textPrimary
        nicknameField.tintColor = OutPickTheme.ColorToken.accent
        nicknameField.font = .systemFont(ofSize: 17, weight: .semibold)
        nicknameField.layer.cornerRadius = 12
        nicknameField.layer.borderWidth = 1
        nicknameField.layer.borderColor = OutPickTheme.ColorToken.borderStrong.cgColor
        nicknameField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        nicknameField.leftViewMode = .always
        nicknameField.autocapitalizationType = .none
        nicknameField.autocorrectionType = .no
        nicknameField.returnKeyType = .done
        nicknameField.delegate = self
        nicknameField.addTarget(self, action: #selector(nicknameChanged), for: .editingChanged)

        countLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        countLabel.textColor = OutPickTheme.ColorToken.textTertiary
        countLabel.textAlignment = .right

        errorLabel.font = .systemFont(ofSize: 13)
        errorLabel.textColor = OutPickTheme.ColorToken.destructive
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true

        nextButton.setTitle("다음", for: .normal)
        nextButton.titleLabel?.font = .boldSystemFont(ofSize: 16)
        nextButton.layer.cornerRadius = 14
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)

        [headerView, nicknamePreviewLabel, nicknameField, countLabel, errorLabel, nextButton]
            .forEach {
                $0.translatesAutoresizingMaskIntoConstraints = false
                view.addSubview($0)
            }

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            nicknamePreviewLabel.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 34),
            nicknamePreviewLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            nicknamePreviewLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),

            nicknameField.topAnchor.constraint(equalTo: nicknamePreviewLabel.bottomAnchor, constant: 28),
            nicknameField.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            nicknameField.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            nicknameField.heightAnchor.constraint(equalToConstant: 54),

            countLabel.topAnchor.constraint(equalTo: nicknameField.bottomAnchor, constant: 8),
            countLabel.leadingAnchor.constraint(equalTo: nicknameField.leadingAnchor),
            countLabel.trailingAnchor.constraint(equalTo: nicknameField.trailingAnchor),

            errorLabel.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 8),
            errorLabel.leadingAnchor.constraint(equalTo: nicknameField.leadingAnchor),
            errorLabel.trailingAnchor.constraint(equalTo: nicknameField.trailingAnchor),

            nextButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            nextButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            nextButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            nextButton.heightAnchor.constraint(equalToConstant: 54)
        ])
    }

    private func bind() {
        viewModel.onStateChanged = { [weak self] state in
            self?.apply(state)
        }
        apply(viewModel.state)
    }

    private func apply(_ state: ProfileSetupViewModel.State) {
        if nicknameField.text != state.nickname {
            nicknameField.text = state.nickname
        }
        countLabel.text = state.nicknameCountText
        nicknamePreviewLabel.text = state.nickname.isEmpty
            ? "YOUR\nNAME"
            : state.nickname
        nicknamePreviewLabel.alpha = state.nickname.isEmpty ? 0.16 : 1
        errorLabel.text = state.errorMessage
        errorLabel.isHidden = state.errorMessage == nil
        nicknameField.isEnabled = state.isCheckingNickname == false
        nextButton.setTitle(state.isCheckingNickname ? "확인 중" : "다음", for: .normal)
        applyPrimaryButtonState(isEnabled: state.isNextEnabled)
    }

    private func applyPrimaryButtonState(isEnabled: Bool) {
        nextButton.isEnabled = isEnabled
        nextButton.backgroundColor = isEnabled
            ? OutPickTheme.ColorToken.accent
            : OutPickTheme.ColorToken.surfaceElevated
        nextButton.setTitleColor(
            isEnabled
                ? OutPickTheme.ColorToken.backgroundBase
                : OutPickTheme.ColorToken.textDisabled,
            for: .normal
        )
    }

    private func presentEntranceIfNeeded() {
        guard hasPresentedEntrance == false else { return }
        hasPresentedEntrance = true
        guard UIAccessibility.isReduceMotionEnabled == false else { return }

        nicknamePreviewLabel.transform = CGAffineTransform(translationX: 0, y: 14)
        nicknamePreviewLabel.alpha = 0
        UIView.animate(
            withDuration: 0.45,
            delay: 0.08,
            options: [.curveEaseOut]
        ) {
            self.nicknamePreviewLabel.transform = .identity
            self.nicknamePreviewLabel.alpha = self.viewModel.state.nickname.isEmpty ? 0.16 : 1
        }
    }

    @objc private func nicknameChanged() {
        viewModel.setNickname(nicknameField.text ?? "")
    }

    @objc private func nextTapped() {
        nicknameField.resignFirstResponder()
        viewModel.nextTapped()
    }

}

extension ProfileSetupViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String
    ) -> Bool {
        let current = textField.text ?? ""
        guard let range = Range(range, in: current) else { return true }
        return current.replacingCharacters(in: range, with: string).count <= 20
    }
}
