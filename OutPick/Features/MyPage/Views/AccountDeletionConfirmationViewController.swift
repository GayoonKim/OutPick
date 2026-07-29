import UIKit

@MainActor
final class AccountDeletionConfirmationViewController: UIViewController {
    private let viewModel: AccountDeletionViewModel
    private let submitButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let errorLabel = UILabel()

    init(viewModel: AccountDeletionViewModel) {
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
    }

    private func configureUI() {
        title = "계정 삭제"
        view.backgroundColor = OutPickTheme.ColorToken.backgroundBase
        navigationController?.setNavigationBarHidden(false, animated: false)
        navigationController?.navigationBar.tintColor = OutPickTheme.ColorToken.accent
        navigationController?.navigationBar.titleTextAttributes = [
            .foregroundColor: OutPickTheme.ColorToken.textPrimary
        ]

        let scrollView = UIScrollView()
        let contentStack = UIStackView()
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        contentStack.axis = .vertical
        contentStack.spacing = 16

        let header = MyPageEditorialHeaderView()
        header.configure(
            eyebrow: "ACCOUNT",
            title: "떠나기 전에\n확인해 주세요",
            subtitle: "삭제 요청 즉시 계정 이용이 중단되며, 7일 동안만 요청을 취소할 수 있어요."
        )

        let notice = makeNoticeCard()

        errorLabel.font = .systemFont(ofSize: 13)
        errorLabel.textColor = OutPickTheme.ColorToken.destructive
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true

        configureDestructiveButton()
        activityIndicator.color = OutPickTheme.ColorToken.backgroundBase
        activityIndicator.hidesWhenStopped = true

        let buttonContent = UIView()
        [submitButton, activityIndicator].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            buttonContent.addSubview($0)
        }
        NSLayoutConstraint.activate([
            submitButton.topAnchor.constraint(equalTo: buttonContent.topAnchor),
            submitButton.leadingAnchor.constraint(equalTo: buttonContent.leadingAnchor),
            submitButton.trailingAnchor.constraint(equalTo: buttonContent.trailingAnchor),
            submitButton.bottomAnchor.constraint(equalTo: buttonContent.bottomAnchor),
            activityIndicator.centerXAnchor.constraint(equalTo: buttonContent.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: buttonContent.centerYAnchor)
        ])

        [header, notice, errorLabel, buttonContent].forEach(contentStack.addArrangedSubview)
        contentStack.setCustomSpacing(28, after: header)
        contentStack.setCustomSpacing(24, after: notice)

        [scrollView, contentStack].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 28),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -24),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -36),
            buttonContent.heightAnchor.constraint(equalToConstant: 54)
        ])
    }

    private func makeNoticeCard() -> UIView {
        let card = UIView()
        card.backgroundColor = OutPickTheme.ColorToken.surfaceBase
        card.layer.cornerRadius = 18
        card.layer.borderWidth = 1
        card.layer.borderColor = OutPickTheme.ColorToken.borderSubtle.cgColor

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 18

        [
            ("person.crop.circle.badge.xmark", "요청 즉시 계정 접근과 공개 프로필이 중단돼요."),
            ("clock.arrow.circlepath", "요청 후 정확히 7일 동안 삭제를 취소할 수 있어요."),
            ("trash", "7일이 지나면 복구할 수 없는 영구 삭제가 시작돼요."),
            ("bubble.left.and.bubble.right", "대화·댓글 기록은 서비스 안전을 위해 작성자 정보가 제거된 형태로 남을 수 있어요.")
        ].forEach { icon, text in
            stack.addArrangedSubview(makeNoticeRow(icon: icon, text: text))
        }

        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -22)
        ])
        return card
    }

    private func makeNoticeRow(icon: String, text: String) -> UIView {
        let imageView = UIImageView(image: UIImage(systemName: icon))
        imageView.tintColor = OutPickTheme.ColorToken.warning
        imageView.contentMode = .scaleAspectFit
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.widthAnchor.constraint(equalToConstant: 22).isActive = true

        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = OutPickTheme.ColorToken.textPrimary
        label.numberOfLines = 0

        let row = UIStackView(arrangedSubviews: [imageView, label])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 14
        return row
    }

    private func configureDestructiveButton() {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "계정 삭제 요청하기"
        configuration.baseBackgroundColor = OutPickTheme.ColorToken.destructive
        configuration.baseForegroundColor = OutPickTheme.ColorToken.textPrimary
        configuration.cornerStyle = .capsule
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            attributes.font = .systemFont(ofSize: 16, weight: .bold)
            return attributes
        }
        submitButton.configuration = configuration
        submitButton.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)
    }

    private func bind() {
        viewModel.onStateChanged = { [weak self] state in
            self?.apply(state)
        }
        apply(viewModel.state)
    }

    private func apply(_ state: AccountDeletionViewModel.State) {
        submitButton.isEnabled = state.isSubmitting == false
        submitButton.configuration?.title = state.isSubmitting ? nil : "계정 삭제 요청하기"
        state.isSubmitting ? activityIndicator.startAnimating() : activityIndicator.stopAnimating()
        errorLabel.text = state.errorMessage
        errorLabel.isHidden = state.errorMessage == nil
        navigationItem.hidesBackButton = state.isSubmitting
    }

    @objc private func submitTapped() {
        let alert = UIAlertController(
            title: "계정 삭제를 요청할까요?",
            message: "요청 즉시 로그아웃되며, 같은 소셜 계정으로 다시 인증해야만 7일 안에 취소할 수 있어요.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "계속 사용하기", style: .cancel))
        alert.addAction(UIAlertAction(title: "삭제 요청", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.viewModel.requestDeletion(presenter: self)
        })
        present(alert, animated: true)
    }
}
