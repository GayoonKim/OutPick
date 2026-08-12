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
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.textColor = OutPickTheme.ColorToken.textSecondary
        label.translatesAutoresizingMaskIntoConstraints = false
        
        return label
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
        contentView.addSubview(nickNameLabel)
        contentView.addSubview(moderationButton)
        NSLayoutConstraint.activate([
            userProfileImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            userProfileImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            userProfileImageView.widthAnchor.constraint(equalToConstant: 42),
            userProfileImageView.heightAnchor.constraint(equalToConstant: 42),
            
            nickNameLabel.leadingAnchor.constraint(equalTo: userProfileImageView.trailingAnchor, constant: 10),
            nickNameLabel.trailingAnchor.constraint(lessThanOrEqualTo: moderationButton.leadingAnchor, constant: -10),
            nickNameLabel.centerYAnchor.constraint(equalTo: userProfileImageView.centerYAnchor),
            moderationButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            moderationButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            moderationButton.widthAnchor.constraint(equalToConstant: 44),
            moderationButton.heightAnchor.constraint(equalToConstant: 44)
        ])
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
