import UIKit

final class BlockedUserCell: UITableViewCell {
    static let reuseID = "BlockedUserCell"
    var onUnblock: (() -> Void)?
    private let avatar = AvatarImageView()
    private let nicknameLabel = UILabel()
    private let unblockButton = UIButton(type: .system)
    private let separator = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.layer.cornerRadius = 28
        avatar.backgroundColor = OutPickTheme.ColorToken.surfaceBase
        avatar.isAccessibilityElement = false
        nicknameLabel.font = UIFontMetrics(forTextStyle: .headline).scaledFont(
            for: MyPageEditorialStyle.serifFont(size: 19, weight: .semibold))
        nicknameLabel.adjustsFontForContentSizeCategory = true
        nicknameLabel.textColor = OutPickTheme.ColorToken.textPrimary
        nicknameLabel.numberOfLines = 0
        nicknameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        var config = UIButton.Configuration.plain()
        config.title = "차단 해제"
        config.baseForegroundColor = OutPickTheme.ColorToken.textPrimary
        config.background.strokeColor = OutPickTheme.ColorToken.borderStrong
        config.background.strokeWidth = 1 / UIScreen.main.scale
        config.background.cornerRadius = 22
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            attributes.font = UIFont.preferredFont(forTextStyle: .caption1)
            return attributes
        }
        unblockButton.configuration = config
        unblockButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        unblockButton.setContentHuggingPriority(.required, for: .horizontal)
        unblockButton.addTarget(self, action: #selector(unblockTapped), for: .touchUpInside)
        separator.backgroundColor = OutPickTheme.ColorToken.borderSubtle
        let row = UIStackView(arrangedSubviews: [avatar, nicknameLabel, unblockButton])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 14
        [row, separator].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 56),
            avatar.heightAnchor.constraint(equalToConstant: 56),
            unblockButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            row.bottomAnchor.constraint(equalTo: separator.topAnchor, constant: -20),
            separator.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(userID: String, nickname: String, avatarPath: String?, isUnblocking: Bool,
                   isEnabled: Bool, manager: any AvatarImageManaging) {
        nicknameLabel.text = nickname
        avatar.configure(userID: userID, path: avatarPath, manager: manager)
        unblockButton.configuration?.title = isUnblocking ? "해제 중" : "차단 해제"
        unblockButton.isEnabled = isEnabled && !isUnblocking
        unblockButton.alpha = unblockButton.isEnabled ? 1 : 0.45
        unblockButton.accessibilityLabel = "\(nickname) 차단 해제"
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatar.resetAvatar()
        onUnblock = nil
    }

    @objc private func unblockTapped() { onUnblock?() }
}
