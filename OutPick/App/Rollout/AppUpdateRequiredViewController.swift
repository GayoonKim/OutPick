import UIKit

@MainActor
final class AppUpdateRequiredViewController: UIViewController {
    private let appStoreURL: URL?
    private let onRetry: () -> Void

    init(appStoreURL: URL?, onRetry: @escaping () -> Void) {
        self.appStoreURL = appStoreURL
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

        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = OutPickTheme.ColorToken.textPrimary
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.text = "새 버전으로 업데이트해 주세요"

        let messageLabel = UILabel()
        messageLabel.font = .systemFont(ofSize: 16)
        messageLabel.textColor = OutPickTheme.ColorToken.textSecondary
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.text = "더 안전하고 안정적인 서비스를 위해 최신 버전이 필요해요."

        let updateButton = makeButton(title: "업데이트", selector: #selector(openAppStore))
        updateButton.isHidden = appStoreURL == nil
        let retryButton = makeButton(title: "다시 확인", selector: #selector(retry))

        let stack = UIStackView(arrangedSubviews: [titleLabel, messageLabel, updateButton, retryButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 14
        stack.setCustomSpacing(28, after: messageLabel)
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            updateButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
            retryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 52)
        ])
    }

    private func makeButton(title: String, selector: Selector) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.baseBackgroundColor = OutPickTheme.ColorToken.accent
        configuration.baseForegroundColor = OutPickTheme.ColorToken.backgroundBase
        configuration.cornerStyle = .medium
        let button = UIButton(configuration: configuration)
        button.addTarget(self, action: selector, for: .touchUpInside)
        return button
    }

    @objc private func openAppStore() {
        guard let appStoreURL else { return }
        UIApplication.shared.open(appStoreURL)
    }

    @objc private func retry() {
        onRetry()
    }
}
