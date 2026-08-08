import UIKit

@MainActor
final class ModerationNoticeViewController: UIViewController {
    private let state: CurrentUserModerationState
    private let onDeleteAccount: () -> Void
    private let onLogout: () -> Void

    init(
        state: CurrentUserModerationState,
        onDeleteAccount: @escaping () -> Void,
        onLogout: @escaping () -> Void
    ) {
        self.state = state
        self.onDeleteAccount = onDeleteAccount
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
        configureContent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    private func configureContent() {
        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false

        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.spacing = 20

        let header = makeHeader()
        let noticeCard = makeNoticeCard()
        let actions = makeActions()

        [header, noticeCard, actions].forEach(contentStack.addArrangedSubview)
        contentStack.setCustomSpacing(28, after: header)
        contentStack.setCustomSpacing(34, after: noticeCard)

        [scrollView, contentStack].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 36),
            contentStack.leadingAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.leadingAnchor,
                constant: 24
            ),
            contentStack.trailingAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.trailingAnchor,
                constant: -24
            ),
            contentStack.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor,
                constant: -36
            )
        ])
    }

    private func makeHeader() -> UIView {
        let eyebrowLabel = UILabel()
        eyebrowLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        eyebrowLabel.textColor = OutPickTheme.ColorToken.warning
        eyebrowLabel.adjustsFontForContentSizeCategory = true
        eyebrowLabel.text = state.status == .suspended
            ? "ACCOUNT SUSPENDED"
            : "ACTIVITY RESTRICTED"

        let titleLabel = UILabel()
        titleLabel.font = MyPageEditorialStyle.serifFont(size: 34, weight: .bold)
        titleLabel.textColor = OutPickTheme.ColorToken.textPrimary
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.text = state.status == .suspended
            ? "계정 이용이\n제한되었어요"
            : "일시적으로 활동이\n제한되었어요"

        let subtitleLabel = UILabel()
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = OutPickTheme.ColorToken.textSecondary
        subtitleLabel.numberOfLines = 0
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.text = state.status == .suspended
            ? "현재 계정으로는 OutPick의 일반 콘텐츠를 이용할 수 없어요."
            : "안전한 커뮤니티 운영을 위해 일부 활동을 잠시 사용할 수 없어요."

        let accentLine = UIView()
        accentLine.backgroundColor = OutPickTheme.ColorToken.warning
        accentLine.heightAnchor.constraint(equalToConstant: 2).isActive = true

        let stack = UIStackView(arrangedSubviews: [eyebrowLabel, titleLabel, subtitleLabel, accentLine])
        stack.axis = .vertical
        stack.spacing = 8
        stack.setCustomSpacing(12, after: titleLabel)
        stack.setCustomSpacing(20, after: subtitleLabel)
        return stack
    }

    private func makeNoticeCard() -> UIView {
        let card = UIView()
        card.backgroundColor = OutPickTheme.ColorToken.surfaceBase
        card.layer.cornerRadius = 18
        card.layer.borderWidth = 1
        card.layer.borderColor = OutPickTheme.ColorToken.warning.withAlphaComponent(0.38).cgColor

        let statusLabel = UILabel()
        statusLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        statusLabel.textColor = OutPickTheme.ColorToken.warning
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.text = state.status == .suspended ? "ACCESS STATUS" : "TEMPORARY RESTRICTION"

        let messageLabel = UILabel()
        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.textColor = OutPickTheme.ColorToken.textPrimary
        messageLabel.numberOfLines = 0
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.text = noticeMessage

        let stack = UIStackView(arrangedSubviews: [statusLabel, messageLabel])
        stack.axis = .vertical
        stack.spacing = 12

        if let supportURL = state.supportURL {
            let supportButton = makeSupportButton(url: supportURL)
            stack.addArrangedSubview(supportButton)
            stack.setCustomSpacing(22, after: messageLabel)
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

    private var noticeMessage: String {
        if state.status == .suspended {
            return state.supportURL == nil
                ? "계정 삭제 또는 로그아웃을 선택할 수 있어요."
                : "제한 사유와 이용 가능 범위는 고객지원에서 확인할 수 있어요."
        }

        let activityMessage = "게시물·댓글·메시지 작성과 방 생성 등 일부 활동이 제한돼요."
        guard let restrictedUntil = state.restrictedUntil else {
            return activityMessage
        }
        return "\(activityMessage)\n\n제한 종료 예정\n\(formattedRestrictionEnd(restrictedUntil))"
    }

    private func formattedRestrictionEnd(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 a h:mm"
        return formatter.string(from: date)
    }

    private func makeSupportButton(url: URL) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.title = "고객지원에서 확인하기"
        configuration.image = UIImage(systemName: "arrow.up.right")
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 8
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = OutPickTheme.ColorToken.warning
        configuration.baseForegroundColor = OutPickTheme.ColorToken.backgroundBase
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            attributes.font = .systemFont(ofSize: 15, weight: .bold)
            return attributes
        }
        button.configuration = configuration
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        button.addAction(UIAction { _ in
            UIApplication.shared.open(url)
        }, for: .touchUpInside)
        return button
    }

    private func makeActions() -> UIView {
        let sectionLabel = UILabel()
        sectionLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        sectionLabel.textColor = OutPickTheme.ColorToken.textTertiary
        sectionLabel.adjustsFontForContentSizeCategory = true
        sectionLabel.text = "ACCOUNT ACTIONS"

        let deleteButton = MyPageActionRowButton(
            title: "계정 삭제",
            subtitle: "삭제 요청 전 세부 내용을 한 번 더 확인해요."
        )
        deleteButton.addAction(UIAction { [weak self] _ in
            self?.onDeleteAccount()
        }, for: .touchUpInside)

        let logoutButton = MyPageActionRowButton(
            title: "로그아웃",
            subtitle: "현재 기기에서 계정 연결을 종료해요."
        )
        logoutButton.addAction(UIAction { [weak self] _ in
            self?.onLogout()
        }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [sectionLabel, deleteButton, logoutButton])
        stack.axis = .vertical
        stack.spacing = 0
        stack.setCustomSpacing(8, after: sectionLabel)
        return stack
    }
}
