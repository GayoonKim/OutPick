import UIKit

@MainActor
final class AccountDeletionPendingViewController: UIViewController {
    private let onLogout: () -> Void

    init(onLogout: @escaping () -> Void) {
        self.onLogout = onLogout
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = OutPickTheme.ColorToken.backgroundBase

        let title = UILabel()
        title.text = "계정 삭제를 처리하고 있어요"
        title.font = .boldSystemFont(ofSize: 24)
        title.textColor = OutPickTheme.ColorToken.textPrimary
        title.textAlignment = .center
        title.numberOfLines = 0

        let message = UILabel()
        message.text = "삭제가 완료될 때까지 앱 기능을 사용할 수 없어요."
        message.font = .systemFont(ofSize: 15)
        message.textColor = OutPickTheme.ColorToken.textSecondary
        message.textAlignment = .center
        message.numberOfLines = 0

        let button = UIButton(type: .system)
        button.setTitle("로그아웃", for: .normal)
        button.titleLabel?.font = .boldSystemFont(ofSize: 16)
        button.backgroundColor = OutPickTheme.ColorToken.accent
        button.setTitleColor(OutPickTheme.ColorToken.backgroundBase, for: .normal)
        button.layer.cornerRadius = 12
        button.addTarget(self, action: #selector(logoutTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [title, message, button])
        stack.axis = .vertical
        stack.spacing = 16
        stack.setCustomSpacing(28, after: message)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            button.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    @objc private func logoutTapped() {
        onLogout()
    }
}
