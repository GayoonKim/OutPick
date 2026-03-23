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
    
    private lazy var userProfileImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(named: "Default_Profile")
        imageView.tintColor = .black
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 12
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.backgroundColor = .systemGray6
        
        return imageView
    }()
    
    private lazy var nickNameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.textColor = .darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        contentView.addSubview(userProfileImageView)
        contentView.addSubview(nickNameLabel)
        NSLayoutConstraint.activate([
            userProfileImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            userProfileImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            userProfileImageView.widthAnchor.constraint(equalToConstant: 42),
            userProfileImageView.heightAnchor.constraint(equalToConstant: 42),
            
            nickNameLabel.leadingAnchor.constraint(equalTo: userProfileImageView.trailingAnchor, constant: 10),
            nickNameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            nickNameLabel.centerYAnchor.constraint(equalTo: userProfileImageView.centerYAnchor)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configureCell(userProfile: LocalUser) {
        nickNameLabel.text = userProfile.nickname
        avatarLoadTask?.cancel()
        avatarLoadTask = nil
        userProfileImageView.image = UIImage(named: "Default_Profile")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarLoadTask?.cancel()
        avatarLoadTask = nil
        userProfileImageView.image = UIImage(named: "Default_Profile")
    }

    func configureCell(userProfile: LocalUser, avatarImageManager: ChatAvatarImageManaging) {
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
}
