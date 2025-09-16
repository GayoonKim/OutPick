//
//  RoomListCollectionViewCell.swift
//  OutPick
//
//  Created by 김가윤 on 10/15/24.
//

import UIKit

class RoomListCollectionViewCell: UICollectionViewCell {
    static let identifier = "RoomListCollectionViewCell"

    let roomImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 8
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    let roomNameLabel: UILabel = {
        let label = UILabel()
        label.font = .boldSystemFont(ofSize: 13)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let roomDescriptionLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var previewStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.clipsToBounds = true
        stackView.backgroundColor = .black
        stackView.layer.cornerRadius = 15
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayout()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupLayout() {
        contentView.addSubview(roomImageView)
        contentView.addSubview(roomNameLabel)
        contentView.addSubview(roomDescriptionLabel)
        contentView.addSubview(previewStackView)

        NSLayoutConstraint.activate([
            roomImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            roomImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            roomImageView.widthAnchor.constraint(equalToConstant: 48),
            roomImageView.heightAnchor.constraint(equalToConstant: 48),

            roomNameLabel.leadingAnchor.constraint(equalTo: roomImageView.trailingAnchor, constant: 12),
            roomNameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            roomNameLabel.centerYAnchor.constraint(equalTo: roomImageView.centerYAnchor),

            roomDescriptionLabel.topAnchor.constraint(equalTo: roomImageView.bottomAnchor, constant: 5),
            roomDescriptionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            roomDescriptionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            previewStackView.topAnchor.constraint(equalTo: roomDescriptionLabel.bottomAnchor, constant: 8),
            previewStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            previewStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            previewStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }
    
    func configure(room: ChatRoom, messages: [ChatMessage]) {
        roomImageView.layer.cornerRadius = 15
        roomImageView.clipsToBounds = true

        roomImageView.image = UIImage(named: "Default_Profile")

        roomNameLabel.text = room.roomName
        
        roomDescriptionLabel.font = .systemFont(ofSize: 13, weight: .light)
        roomDescriptionLabel.text = room.roomDescription

        previewStackView.arrangedSubviews.forEach { view in
            previewStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if messages.isEmpty {
            let placeholder = UILabel()
            placeholder.text = "대화를 시작해 보세요 👋"
            placeholder.textColor = .secondaryLabel
            placeholder.font = .systemFont(ofSize: 14, weight: .medium)
            placeholder.textColor = .white
            placeholder.textAlignment = .center
            placeholder.heightAnchor.constraint(equalToConstant: 50).isActive = true
            previewStackView.addArrangedSubview(placeholder)
        } else {
            let myNickname = LoginManager.shared.currentUserProfile?.nickname
            for message in messages {
                let preview = MessagePreviewView()
                let isMine = (message.senderNickname == myNickname)
                preview.configure(with: message, isMine: isMine)
                previewStackView.addArrangedSubview(preview)
            }
        }
    }
}

// MARK: - MessagePreviewView
private class MessagePreviewView: UIView {
    private let profileImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 10
        imageView.image = UIImage(named: "Default_Profile")
        return imageView
    }()
    
    private let nicknameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let bubbleView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.systemGray5
        view.layer.cornerRadius = 12
        return view
    }()
    
    private let messageLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        return label
    }()
    
    private let hStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .top
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let vStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    private var leadingConstraint: NSLayoutConstraint?
    private var trailingConstraint: NSLayoutConstraint?
    private var bubbleTopToNickname: NSLayoutConstraint?
    private var bubbleTopToTop: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayout()
    }
    
    private func setupLayout() {
        self.backgroundColor = .black

        addSubview(profileImageView)
        addSubview(nicknameLabel)
        addSubview(bubbleView)
        bubbleView.addSubview(messageLabel)
        
        profileImageView.translatesAutoresizingMaskIntoConstraints = false
        nicknameLabel.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        
        
        bubbleTopToNickname = bubbleView.topAnchor.constraint(equalTo: nicknameLabel.bottomAnchor, constant: 10)
        bubbleTopToTop = bubbleView.topAnchor.constraint(equalTo: topAnchor, constant: 10)

        bubbleTopToNickname?.isActive = true // 기본은 상대방 메시지 기준
        NSLayoutConstraint.activate([
            profileImageView.heightAnchor.constraint(equalToConstant: 36),
            profileImageView.widthAnchor.constraint(equalToConstant: 36),
            profileImageView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            profileImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),

            nicknameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            nicknameLabel.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 5),
            nicknameLabel.bottomAnchor.constraint(equalTo: bubbleView.topAnchor, constant: -5),
            
//            bubbleView.topAnchor.constraint(equalTo: nicknameLabel.bottomAnchor, constant: 10),
            bubbleView.widthAnchor.constraint(lessThanOrEqualTo: self.widthAnchor, multiplier: 0.7),
            bubbleView.heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
            
            messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 4),
            messageLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -4),
            messageLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 8),
            messageLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -8),
            
            bubbleView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
        
        // 미리 leading/trailing 제약 저장
        leadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 5)
        trailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10)
    }
    
    func configure(with message: ChatMessage, isMine: Bool) {
        nicknameLabel.text = message.senderNickname
        messageLabel.text = message.msg
        
        if isMine {
            profileImageView.isHidden = true
            nicknameLabel.isHidden = true
            bubbleView.backgroundColor = .systemBlue

            bubbleTopToNickname?.isActive = false
            bubbleTopToTop?.isActive = true

            leadingConstraint?.isActive = false
            trailingConstraint?.isActive = true
        } else {
            profileImageView.isHidden = false
            nicknameLabel.isHidden = false
            bubbleView.backgroundColor = UIColor(white: 0.2, alpha: 1.0)

            bubbleTopToTop?.isActive = false
            bubbleTopToNickname?.isActive = true

            trailingConstraint?.isActive = false
            leadingConstraint?.isActive = true
        }
    }
}
