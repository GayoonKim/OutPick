//
//  ChatCell.swift
//  OutPick
//
//  Created by 김가윤 on 3/12/25.
//

import UIKit

class ChatCell: UICollectionViewCell {
    static let reuseIdentifier = "ChatCell"
    
    private lazy var vStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.distribution = .equalSpacing
        stackView.alignment = .center
        stackView.spacing = 8
        
        return stackView
    }()
    
    private lazy var profileImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 20
        imageView.image = UIImage(named: "Default_Profile.png")
        
        return imageView
    }()
    
    private lazy var hStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.distribution = .fillProportionally
        stackView.alignment = .leading
        stackView.spacing = 8
        
        return stackView
    }()
    
    private lazy var nicknameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .medium)
        return label
    }()
    
    private lazy var contentTextView: UITextView = {
        let textView = UITextView()
        textView.font = .systemFont(ofSize: 14)
        textView.isScrollEnabled = false
        textView.isEditable = false
        textView.dataDetectorTypes = []
        textView.layer.cornerRadius = 20
        
        return textView
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        vStackView.addArrangedSubview(profileImageView)
        hStackView.addArrangedSubview(nicknameLabel)
        hStackView.addArrangedSubview(contentTextView)
        vStackView.addArrangedSubview(hStackView)
        contentView.addSubview(vStackView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(_ message: ChatMessage) {
        nicknameLabel.text = message.senderNickname
        
        contentTextView.text = message.msg
        contentTextView.textAlignment = message.senderNickname == UserProfile.shared.nickname ? .left : .right
        contentTextView.backgroundColor = message.senderNickname == UserProfile.shared.nickname ? .systemBlue : .lightGray
        
        NSLayoutConstraint.activate([
            vStackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            vStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            vStackView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.75),
            message.senderNickname == UserProfile.shared.nickname ? vStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10) : vStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10)
        ])
    }
}

