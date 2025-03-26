//
//  ChatMessageCell.swift
//  OutPick
//
//  Created by 김가윤 on 3/14/25.
//

import Foundation
import UIKit

class ChatMessageCell: UICollectionViewCell {
    static let resuseIdentifier = "ChatMessageCell"
    
    private let profileImageView: UIImageView = {
        var imageView = UIImageView()
        imageView.layer.cornerRadius = 10
        imageView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.image = UIImage(named: "Default_Profile")
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        return imageView
    }()
    
    private let nickNameLabel : UILabel = {
        var label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .black
        label.translatesAutoresizingMaskIntoConstraints = false
        
        return label
    }()
    
    private let messageLabel: UILabel = {
        var label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.numberOfLines = 0
        label.backgroundColor = .clear
        label.textColor = .black
        label.translatesAutoresizingMaskIntoConstraints = false
        
        return label
    }()
    
    private let messageImageView: UIImageView = {
        var imageView = UIImageView()
        imageView.contentMode = .scaleToFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 12
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        return imageView
    }()
    
    private let bubbleView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    private var bubbleViewTrailingConstraint: NSLayoutConstraint?
    private var bubbleViewLeadingConstraint: NSLayoutConstraint?
    private var bubbleViewTopConstraint: NSLayoutConstraint?
    
    private var messageImageViewTrailingConstraint: NSLayoutConstraint?
    private var messageImageViewLeadingConstraint: NSLayoutConstraint?
    private var messageImageViewTopConstraint: NSLayoutConstraint?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        contentView.addSubview(profileImageView)
        contentView.addSubview(nickNameLabel)
        contentView.addSubview(bubbleView)
        contentView.addSubview(messageImageView)
        bubbleView.addSubview(messageLabel)
        
        NSLayoutConstraint.activate([
            profileImageView.widthAnchor.constraint(equalToConstant: 40),
            profileImageView.heightAnchor.constraint(equalToConstant: 40),
            profileImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            profileImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            
            nickNameLabel.topAnchor.constraint(equalTo: profileImageView.topAnchor),
            nickNameLabel.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 5),
            
            messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 8),
            messageLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 8),
            messageLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -8),
            messageLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -8)
        ])
        
        // 기본 bubbleView 제약조건 설정
        bubbleViewLeadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 5)
        bubbleViewTrailingConstraint = bubbleView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20)
        bubbleViewTopConstraint = bubbleView.topAnchor.constraint(equalTo: nickNameLabel.bottomAnchor, constant: 5)
        
        // 기본 messageImageView 제약조건 설정
        messageImageViewLeadingConstraint = messageImageView.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 5)
        messageImageViewTrailingConstraint = messageImageView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20)
        messageImageViewTopConstraint = messageImageView.topAnchor.constraint(equalTo: nickNameLabel.bottomAnchor, constant: 5)
        
        NSLayoutConstraint.activate([
            bubbleViewLeadingConstraint,
            bubbleViewTrailingConstraint,
            bubbleViewTopConstraint,
            
            messageImageViewLeadingConstraint,
            messageImageViewTrailingConstraint,
            messageImageViewTopConstraint
        ].compactMap{ $0 })
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        messageLabel.text = nil
        nickNameLabel.text = nil
        messageLabel.textAlignment = .left
        profileImageView.isHidden = false
        nickNameLabel.isHidden = false
        bubbleView.backgroundColor = UIColor(white: 0.1, alpha: 0.03)
        
        NSLayoutConstraint.deactivate([
            bubbleViewLeadingConstraint,
            bubbleViewTrailingConstraint,
            bubbleViewTopConstraint
        ].compactMap{ $0 })
    }
    
    func configureWithMessage(with message: ChatMessage) {
        messageLabel.text = message.msg
        messageImageView.isHidden = true
        
        if let nickName = UserProfile.shared.nickname,
           nickName == message.senderNickname {
            // 본인이 보낸 메시지
            bubbleView.backgroundColor = .systemBlue
            profileImageView.isHidden = true
            nickNameLabel.isHidden = true
            messageLabel.textAlignment = .right
            
            // 기본 제약조건 업데이트
            bubbleViewLeadingConstraint = bubbleView.leadingAnchor.constraint(greaterThanOrEqualTo: profileImageView.leadingAnchor, constant: 5)
            bubbleViewLeadingConstraint?.constant = 20
            bubbleViewTrailingConstraint?.constant = -8
            bubbleViewTopConstraint?.constant = 8
        } else {
            // 상대방이 보낸 메시지
            nickNameLabel.text = message.senderNickname
            bubbleView.backgroundColor = UIColor(white: 0.1, alpha: 0.03)
            
            // 기본 제약조건으로 복원
            bubbleViewLeadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 5)
            bubbleViewLeadingConstraint?.constant = 5
            bubbleViewTrailingConstraint?.constant = -20
            bubbleViewTopConstraint?.constant = 5
        }
        
        // 제약조건 활성화
        NSLayoutConstraint.activate([
            bubbleViewLeadingConstraint,
            bubbleViewTrailingConstraint,
            bubbleViewTopConstraint
        ].compactMap{ $0 })
        
        self.setNeedsLayout()
        self.layoutIfNeeded()
    }
    
    func configureWithImage(with message: ChatMessage) {
//        messageImageView.image = image
        messageImageView.isHidden = false
        
        print("ㅋㅋ configureWithImage 호출 ㅋㅋ")
    }
}

