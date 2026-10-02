import UIKit

final class ChatSearchUIView: UIView {
    private let titleLabel = UILabel()
    private let noticeLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let olderButton = UIButton(type: .system)
    private let newerButton = UIButton(type: .system)
    private let actionButton = UIButton(type: .system)
    private let capsule = UIView()
    private let accessoryRow = UIStackView()
    var onPreviousTapped: (() -> Void)?
    var onNextTapped: (() -> Void)?
    var onActionTapped: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = OutPickTheme.ColorToken.backgroundBase
        capsule.backgroundColor = OutPickTheme.ColorToken.backgroundRaised
        capsule.layer.cornerRadius = 32
        capsule.layer.cornerCurve = .continuous
        capsule.layer.borderWidth = 1
        capsule.layer.borderColor = OutPickTheme.ColorToken.borderSubtle.cgColor
        titleLabel.font = .monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = OutPickTheme.ColorToken.textPrimary
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.8
        titleLabel.accessibilityIdentifier = "chat.search.count"
        noticeLabel.font = .systemFont(ofSize: 12)
        noticeLabel.textColor = OutPickTheme.ColorToken.textSecondary
        noticeLabel.numberOfLines = 2
        let symbol = UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold)
        for (button, name, label) in [(olderButton, "chevron.up", "이전 검색 결과"),
                                       (newerButton, "chevron.down", "다음 검색 결과")] {
            button.setImage(UIImage(systemName: name, withConfiguration: symbol), for: .normal)
            button.backgroundColor = OutPickTheme.ColorToken.surfacePressed
            button.tintColor = OutPickTheme.ColorToken.textPrimary
            button.layer.cornerRadius = 22
            button.layer.cornerCurve = .continuous
            button.accessibilityLabel = label
            button.translatesAutoresizingMaskIntoConstraints = false
            capsule.addSubview(button)
        }
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        capsule.addSubview(titleLabel)
        capsule.addSubview(spinner)
        actionButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        actionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        accessoryRow.addArrangedSubview(noticeLabel)
        accessoryRow.addArrangedSubview(actionButton)
        accessoryRow.spacing = 8
        accessoryRow.alignment = .center
        let stack = UIStackView(arrangedSubviews: [capsule, accessoryRow])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            capsule.heightAnchor.constraint(equalToConstant: 64),
            newerButton.trailingAnchor.constraint(equalTo: capsule.trailingAnchor, constant: -10),
            newerButton.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
            olderButton.trailingAnchor.constraint(equalTo: newerButton.leadingAnchor, constant: -8),
            olderButton.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
            olderButton.widthAnchor.constraint(equalToConstant: 44),
            olderButton.heightAnchor.constraint(equalToConstant: 44),
            newerButton.widthAnchor.constraint(equalToConstant: 44),
            newerButton.heightAnchor.constraint(equalToConstant: 44),
            titleLabel.centerXAnchor.constraint(equalTo: capsule.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: capsule.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: olderButton.leadingAnchor, constant: -8),
            spinner.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
            spinner.leadingAnchor.constraint(equalTo: capsule.leadingAnchor, constant: 16)
        ])
        let actionHeight = actionButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        actionHeight.priority = .defaultHigh
        actionHeight.isActive = true
        olderButton.addTarget(self, action: #selector(older), for: .touchUpInside)
        newerButton.addTarget(self, action: #selector(newer), for: .touchUpInside)
        actionButton.addTarget(self, action: #selector(searchActionTapped), for: .touchUpInside)
        updateSearchResult(ChatSearchPresentationState())
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func older() { onPreviousTapped?() }
    @objc private func newer() { onNextTapped?() }
    @objc private func searchActionTapped() { onActionTapped?() }
    func updateSearchResult(_ state: ChatSearchPresentationState) {
        // 이동·선로딩 중에도 숫자와 버튼 위치를 유지하고 확보 개수만 갱신한다.
        titleLabel.text = state.title
        noticeLabel.text = state.notice; noticeLabel.isHidden = state.notice == nil
        olderButton.isEnabled = state.canMoveOlder; newerButton.isEnabled = state.canMoveNewer
        olderButton.alpha = state.canMoveOlder ? 1 : 0.35
        newerButton.alpha = state.canMoveNewer ? 1 : 0.35
        actionButton.setTitle(state.actionTitle, for: .normal); actionButton.isHidden = state.actionTitle == nil
        accessoryRow.isHidden = state.notice == nil && state.actionTitle == nil
        state.showsLoadingIndicator ? spinner.startAnimating() : spinner.stopAnimating()
    }
}
