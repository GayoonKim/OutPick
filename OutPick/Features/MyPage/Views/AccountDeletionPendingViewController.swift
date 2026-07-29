import UIKit

@MainActor
final class AccountDeletionPendingViewController: UIViewController {
    private let viewModel: AccountDeletionPendingViewModel
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let deadlineLabel = UILabel()
    private let statusLabel = UILabel()
    private let errorLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let primaryButton = UIButton(type: .system)
    private let retryButton = UIButton(type: .system)

    init(viewModel: AccountDeletionPendingViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        bind()
        viewModel.load()
    }

    private func configureUI() {
        view.backgroundColor = OutPickTheme.ColorToken.backgroundBase

        let iconContainer = UIView()
        iconContainer.backgroundColor = OutPickTheme.ColorToken.surfaceBase
        iconContainer.layer.cornerRadius = 36
        iconContainer.layer.borderWidth = 1
        iconContainer.layer.borderColor = OutPickTheme.ColorToken.borderSubtle.cgColor
        iconContainer.widthAnchor.constraint(equalToConstant: 72).isActive = true
        iconContainer.heightAnchor.constraint(equalToConstant: 72).isActive = true

        let icon = UIImageView(image: UIImage(systemName: "hourglass"))
        icon.tintColor = OutPickTheme.ColorToken.warning
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 30),
            icon.heightAnchor.constraint(equalToConstant: 30)
        ])

        statusLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        statusLabel.textColor = OutPickTheme.ColorToken.warning
        statusLabel.textAlignment = .center

        titleLabel.text = "계정 삭제가\n예약됐어요"
        titleLabel.font = MyPageEditorialStyle.serifFont(size: 34, weight: .bold)
        titleLabel.textColor = OutPickTheme.ColorToken.textPrimary
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.textColor = OutPickTheme.ColorToken.textSecondary
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        deadlineLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        deadlineLabel.textColor = OutPickTheme.ColorToken.textPrimary
        deadlineLabel.textAlignment = .center
        deadlineLabel.numberOfLines = 0

        errorLabel.font = .systemFont(ofSize: 13)
        errorLabel.textColor = OutPickTheme.ColorToken.destructive
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true

        activityIndicator.color = OutPickTheme.ColorToken.accent

        var primaryConfiguration = UIButton.Configuration.filled()
        primaryConfiguration.cornerStyle = .capsule
        primaryConfiguration.baseBackgroundColor = OutPickTheme.ColorToken.accent
        primaryConfiguration.baseForegroundColor = OutPickTheme.ColorToken.backgroundBase
        primaryConfiguration.title = "삭제 요청 취소하기"
        primaryButton.configuration = primaryConfiguration
        primaryButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        primaryButton.heightAnchor.constraint(equalToConstant: 54).isActive = true
        primaryButton.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)

        retryButton.setTitle("상태 다시 확인", for: .normal)
        retryButton.setTitleColor(OutPickTheme.ColorToken.accent, for: .normal)
        retryButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            iconContainer, statusLabel, titleLabel, messageLabel,
            deadlineLabel, activityIndicator, errorLabel, retryButton, primaryButton
        ])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 14
        stack.setCustomSpacing(22, after: iconContainer)
        stack.setCustomSpacing(8, after: statusLabel)
        stack.setCustomSpacing(16, after: titleLabel)
        stack.setCustomSpacing(26, after: deadlineLabel)
        stack.setCustomSpacing(24, after: retryButton)
        iconContainer.setContentHuggingPriority(.required, for: .horizontal)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor)
        ])
    }

    private func bind() {
        viewModel.onStateChanged = { [weak self] state in
            self?.apply(state)
        }
        apply(viewModel.state)
    }

    private func apply(_ state: AccountDeletionPendingViewModel.State) {
        statusLabel.text = statusText(for: state.status)
        messageLabel.text = state.message
        deadlineLabel.text = deadlineText(for: state)
        deadlineLabel.isHidden = deadlineLabel.text == nil
        errorLabel.text = state.errorMessage
        errorLabel.isHidden = state.errorMessage == nil
        retryButton.isHidden = state.errorMessage == nil
        state.isLoading ? activityIndicator.startAnimating() : activityIndicator.stopAnimating()

        let isFinished = state.status == .completed || state.status == .cancelled
        primaryButton.isHidden = state.canCancel == false && isFinished == false
        primaryButton.isEnabled = state.isCancelling == false
        primaryButton.configuration?.title = isFinished
            ? "로그인 화면으로"
            : (state.isCancelling ? "취소 처리 중…" : "삭제 요청 취소하기")
        if isFinished {
            primaryButton.isHidden = false
        }
    }

    private func statusText(for status: AccountDeletionStatus) -> String {
        switch status {
        case .grace: return "7-DAY CANCELLATION"
        case .finalizing, .retryPending: return "DELETION IN PROGRESS"
        case .completed: return "DELETION COMPLETED"
        case .cancelled: return "REQUEST CANCELLED"
        }
    }

    private func deadlineText(for state: AccountDeletionPendingViewModel.State) -> String? {
        guard state.status == .grace, let date = state.cancelableUntil else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 a h:mm까지 취소 가능"
        return formatter.string(from: date)
    }

    @objc private func primaryTapped() {
        let state = viewModel.state
        if state.status == .completed || state.status == .cancelled {
            viewModel.finishedTapped()
            return
        }

        let alert = UIAlertController(
            title: "삭제 요청을 취소할까요?",
            message: "본인 확인 후 계정을 다시 사용할 수 있어요.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "아니요", style: .cancel))
        alert.addAction(UIAlertAction(title: "취소하기", style: .default) { [weak self] _ in
            guard let self else { return }
            self.viewModel.cancelDeletion(presenter: self)
        })
        present(alert, animated: true)
    }

    @objc private func retryTapped() {
        viewModel.load()
    }
}
