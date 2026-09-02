//
//  ParticipantListCollectionViewCell.swift
//  OutPick
//
//  Created by 김가윤 on 5/17/25.
//

import UIKit

class ParticipantListCell: UICollectionViewCell {
    static let reuseIdentifier = "ParticipantListCell"
    private var avatarLoadTask: Task<Void, Never>?
    private var onModerate: (() -> Void)?
    
    private lazy var userProfileImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(named: "Default_Profile")
        imageView.tintColor = OutPickTheme.ColorToken.iconSecondary
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 12
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.backgroundColor = OutPickTheme.ColorToken.surfaceElevated
        
        return imageView
    }()
    
    private lazy var nickNameLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textColor = OutPickTheme.ColorToken.textSecondary
        return label
    }()

    private lazy var roleBadgeLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .caption2)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = OutPickTheme.ColorToken.accent
        label.backgroundColor = OutPickTheme.ColorToken.surfaceElevated
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var labelsStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [nickNameLabel, roleBadgeLabel])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var moderationButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        button.tintColor = OutPickTheme.ColorToken.iconSecondary
        button.accessibilityLabel = "사용자 관리"
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(moderationTapped), for: .touchUpInside)
        return button
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        contentView.addSubview(userProfileImageView)
        contentView.addSubview(labelsStack)
        contentView.addSubview(moderationButton)
        NSLayoutConstraint.activate([
            userProfileImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            userProfileImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            userProfileImageView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 9),
            userProfileImageView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -9),
            userProfileImageView.widthAnchor.constraint(equalToConstant: 42),
            userProfileImageView.heightAnchor.constraint(equalToConstant: 42),

            labelsStack.leadingAnchor.constraint(equalTo: userProfileImageView.trailingAnchor, constant: 10),
            labelsStack.trailingAnchor.constraint(lessThanOrEqualTo: moderationButton.leadingAnchor, constant: -8),
            labelsStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            labelsStack.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 8),
            labelsStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8),
            roleBadgeLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 20),
            roleBadgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 28),
            moderationButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            moderationButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            moderationButton.widthAnchor.constraint(equalToConstant: 44),
            moderationButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        let attributes = super.preferredLayoutAttributesFitting(layoutAttributes)
        let targetSize = CGSize(
            width: layoutAttributes.size.width,
            height: UIView.layoutFittingCompressedSize.height
        )
        attributes.size.height = max(
            60,
            ceil(contentView.systemLayoutSizeFitting(
                targetSize,
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height)
        )
        return attributes
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configureCell(userProfile: LocalChatUser) {
        print(#function, "불러온 사용자 프로필 => \(userProfile)")
        let nickname = userProfile.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        nickNameLabel.text = nickname.isEmpty ? Self.fallbackDisplayName() : nickname
        avatarLoadTask?.cancel()
        avatarLoadTask = nil
        userProfileImageView.image = UIImage(named: "Default_Profile")
        roleBadgeLabel.isHidden = true
        roleBadgeLabel.text = nil
    }

    func configureCell(
        participant: ChatRoomParticipant,
        currentUserID: String,
        avatarImageManager: AvatarImageManaging
    ) {
        configureCell(userProfile: participant.user, avatarImageManager: avatarImageManager)
        var badges: [String] = []
        if participant.userID == currentUserID { badges.append("나") }
        switch participant.role {
        case .owner: badges.append("방장")
        case .moderator: badges.append("관리자")
        case .member: break
        }
        roleBadgeLabel.text = badges.joined(separator: " · ")
        roleBadgeLabel.isHidden = badges.isEmpty
        accessibilityLabel = [participant.user.nickname, badges.joined(separator: ", ")]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    func configureModeration(isVisible: Bool, onTap: (() -> Void)?) {
        moderationButton.isHidden = !isVisible
        onModerate = isVisible ? onTap : nil
    }

    @objc private func moderationTapped() {
        onModerate?()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarLoadTask?.cancel()
        avatarLoadTask = nil
        userProfileImageView.image = UIImage(named: "Default_Profile")
        configureModeration(isVisible: false, onTap: nil)
        roleBadgeLabel.isHidden = true
        roleBadgeLabel.text = nil
    }

    func configureCell(userProfile: LocalChatUser, avatarImageManager: AvatarImageManaging) {
        configureCell(userProfile: userProfile)

        guard let path = userProfile.profileImagePath, !path.isEmpty else { return }

        avatarLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }

            if let cached = await avatarImageManager.cachedAvatar(for: path) {
                guard !Task.isCancelled else { return }
                self.userProfileImageView.image = cached
                return
            }

            do {
                let image = try await avatarImageManager.loadAvatar(for: path, maxBytes: 3 * 1024 * 1024)
                guard !Task.isCancelled else { return }
                self.userProfileImageView.image = image
            } catch {
                self.userProfileImageView.image = UIImage(named: "Default_Profile")
            }
        }
    }

    private static func fallbackDisplayName() -> String {
        "알 수 없는 사용자"
    }
}
