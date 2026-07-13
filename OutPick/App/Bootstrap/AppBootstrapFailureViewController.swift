import UIKit

@MainActor
final class AppBootstrapFailureViewController: UIViewController {
    private let onRetry: () -> Void

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 24, weight: .bold)
        label.textColor = OutPickTheme.ColorToken.textPrimary
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = "앱 데이터를 준비하지 못했어요"
        label.accessibilityIdentifier = "app.bootstrap.failure.title"
        return label
    }()

    private lazy var messageLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 16, weight: .regular)
        label.textColor = OutPickTheme.ColorToken.textSecondary
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = "잠시 후 다시 시도해주세요. 문제가 계속되면 앱을 다시 실행해주세요."
        label.accessibilityIdentifier = "app.bootstrap.failure.message"
        return label
    }()

    private lazy var retryButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "다시 시도"
        configuration.baseBackgroundColor = OutPickTheme.ColorToken.accent
        configuration.baseForegroundColor = OutPickTheme.ColorToken.backgroundBase
        configuration.cornerStyle = .medium
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 24, bottom: 14, trailing: 24)

        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.accessibilityIdentifier = "app.bootstrap.failure.retry"
        button.addTarget(self, action: #selector(retryButtonTapped), for: .touchUpInside)
        return button
    }()

    init(onRetry: @escaping () -> Void) {
        self.onRetry = onRetry
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = OutPickTheme.ColorToken.backgroundBase
        view.accessibilityIdentifier = "app.bootstrap.failure.root"
        configureLayout()
    }

    private func configureLayout() {
        let stackView = UIStackView(arrangedSubviews: [titleLabel, messageLabel, retryButton])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 16
        stackView.setCustomSpacing(28, after: messageLabel)
        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            stackView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32),
            stackView.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            retryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 52)
        ])
    }

    @objc private func retryButtonTapped() {
        retryButton.isEnabled = false
        onRetry()
    }
}
