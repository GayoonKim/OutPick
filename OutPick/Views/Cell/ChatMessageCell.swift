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
        imageView.layer.cornerRadius = 20
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
    
    private let bubbleView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 12
        view.backgroundColor = .white
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        contentView.addSubview(profileImageView)
        contentView.addSubview(nickNameLabel)
        contentView.addSubview(bubbleView)
        bubbleView.addSubview(messageLabel)
        
        NSLayoutConstraint.activate([
            profileImageView.widthAnchor.constraint(equalToConstant: 40),
            profileImageView.heightAnchor.constraint(equalToConstant: 40),
            profileImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            profileImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            
            nickNameLabel.topAnchor.constraint(equalTo: profileImageView.topAnchor),
            nickNameLabel.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 5),
            
            bubbleView.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 5),
            bubbleView.topAnchor.constraint(equalTo: nickNameLabel.bottomAnchor, constant: 5),
            bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 8),
            messageLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 8),
            messageLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -8),
            messageLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -8)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(with message: ChatMessage) {
        nickNameLabel.text = message.senderNickname
        messageLabel.text = message.msg
    }
}
