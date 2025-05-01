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
    
    private let bubbleView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    private let imagesPreviewCollectionView: ChatImagePreviewCollectionView = {
        let view = ChatImagePreviewCollectionView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        view.backgroundColor = .clear
        return view
    }()
    
    private let failedIconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "exclamationmark.circle.fill")
        imageView.tintColor = .red
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isHidden = true
        
        return imageView
    }()
    
    private var bubbleViewTrailingConstraint: NSLayoutConstraint?
    private var bubbleViewLeadingConstraint: NSLayoutConstraint?
    private var bubbleViewTopConstraint: NSLayoutConstraint?
    private var bubbleViewBottomConstraint: NSLayoutConstraint?

    private var imagePreviewCollectionViewTopConstraint: NSLayoutConstraint?
    private var imagePreviewCollectionViewLeadingConstraint: NSLayoutConstraint?
    private var imagePreviewCollectionViewTrailingConstraint: NSLayoutConstraint?
    private var imagePreviewCollectionViewBottomConstraint: NSLayoutConstraint?
    private var imagePreviewCollectionViewWidthConstraint: NSLayoutConstraint?
    private var imagePreviewCollectionViewHeightConstraint: NSLayoutConstraint?
    
    private var failedIconImageViewCenterYConstraint: NSLayoutConstraint?
    private var failedIconImageViewTrainlingConstraint: NSLayoutConstraint?
    
    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.addSubview(profileImageView)
        contentView.addSubview(nickNameLabel)
        contentView.addSubview(bubbleView)
        contentView.addSubview(imagesPreviewCollectionView)
        contentView.addSubview(failedIconImageView)
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
            messageLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            
            failedIconImageView.widthAnchor.constraint(equalToConstant: 20),
            failedIconImageView.heightAnchor.constraint(equalToConstant: 20),
//            failedIconImageView.centerYAnchor.constraint(equalTo: bubbleView.centerYAnchor),
//            failedIconImageView.trailingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: -2)
        ])
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
        imagesPreviewCollectionView.isHidden = true
        
        NSLayoutConstraint.deactivate([
            bubbleViewLeadingConstraint,
            bubbleViewTrailingConstraint,
            bubbleViewTopConstraint,
            bubbleViewBottomConstraint,
            
            imagePreviewCollectionViewTopConstraint,
            imagePreviewCollectionViewLeadingConstraint,
            imagePreviewCollectionViewTrailingConstraint,
            imagePreviewCollectionViewBottomConstraint,
            imagePreviewCollectionViewWidthConstraint,
            imagePreviewCollectionViewHeightConstraint,
            
            failedIconImageViewCenterYConstraint,
            failedIconImageViewTrainlingConstraint
        ].compactMap{ $0 })
    }
    
    func configureWithMessage(with message: ChatMessage) {
        messageLabel.text = message.msg
        imagesPreviewCollectionView.isHidden = true
        
        let containerWidth = contentView.frame.width * 0.7
        
        if let nickName = UserProfile.shared.nickname,
           nickName == message.senderNickname {
            // 본인이 보낸 메시지
            bubbleView.backgroundColor = .systemBlue
            profileImageView.isHidden = true
            nickNameLabel.isHidden = true
            messageLabel.textAlignment = .right
            
            // 기본 제약조건 업데이트
            bubbleViewLeadingConstraint = bubbleView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 20)
            bubbleViewTrailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8)
            bubbleViewTopConstraint = bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8)
            bubbleViewBottomConstraint = bubbleView.bottomAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 8)
            bubbleView.widthAnchor.constraint(lessThanOrEqualToConstant: containerWidth).isActive = true
            

            
            if message.isFailed {
                failedIconImageView.isHidden = false
                
                failedIconImageViewCenterYConstraint = failedIconImageView.centerYAnchor.constraint(equalTo: bubbleView.centerYAnchor)
                failedIconImageViewTrainlingConstraint = failedIconImageView.trailingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: -2)
            }
        } else {
            // 상대방이 보낸 메시지
            nickNameLabel.text = message.senderNickname
            bubbleView.backgroundColor = UIColor(white: 0.1, alpha: 0.03)
            
            // 기본 제약조건으로 복원
            bubbleViewLeadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 5)
            bubbleViewTrailingConstraint = bubbleView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20)
            bubbleViewTopConstraint = bubbleView.topAnchor.constraint(equalTo: nickNameLabel.bottomAnchor, constant: 5)
            bubbleViewBottomConstraint = bubbleView.bottomAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 8)
            bubbleView.widthAnchor.constraint(lessThanOrEqualToConstant: containerWidth).isActive = true
        }
        
        // 제약조건 활성화
        NSLayoutConstraint.activate([
            bubbleViewLeadingConstraint,
            bubbleViewTrailingConstraint,
            bubbleViewTopConstraint,
            bubbleViewBottomConstraint,
            
            failedIconImageViewCenterYConstraint,
            failedIconImageViewTrainlingConstraint
        ].compactMap{ $0 })
        
        self.setNeedsLayout()
        self.layoutIfNeeded()
    }
    
    func configureWithImage(with message: ChatMessage) {
        bubbleView.isHidden = true
        messageLabel.isHidden = true
        imagesPreviewCollectionView.isHidden = false
        
        if let nickName = UserProfile.shared.nickname {
            let images = message.attachments.compactMap {
                if let imageData = $0.fileData {
                    return UIImage(data: imageData)
                }
                return nil
            }
            
            let containerWidth = contentView.frame.width * 0.7
            let rows = calculateRowCountWithImage(images.count)
            
            var contentHeight: CGFloat {
                if images.count == 1 {
                    return containerWidth
                } else {
                    return rows.reduce(0) { $0 + (containerWidth / CGFloat($1)) }
                }
            }
            
            if nickName == message.senderNickname {
                // 본인이 보낸 사진
                profileImageView.isHidden = true
                
                imagePreviewCollectionViewTopConstraint = imagesPreviewCollectionView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8)
                imagePreviewCollectionViewTrailingConstraint = imagesPreviewCollectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8)
                imagePreviewCollectionViewBottomConstraint = imagesPreviewCollectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
                imagePreviewCollectionViewWidthConstraint = imagesPreviewCollectionView.widthAnchor.constraint(equalToConstant: containerWidth)
                imagePreviewCollectionViewHeightConstraint = imagesPreviewCollectionView.heightAnchor.constraint(equalToConstant: contentHeight)
                
                if message.isFailed {
                    failedIconImageView.isHidden = false
                    
                    failedIconImageViewCenterYConstraint = failedIconImageView.centerYAnchor.constraint(equalTo: imagesPreviewCollectionView.centerYAnchor)
                    failedIconImageViewTrainlingConstraint = failedIconImageView.trailingAnchor.constraint(equalTo: imagesPreviewCollectionView.leadingAnchor, constant: -2)
                }
            } else {
                nickNameLabel.isHidden = false
                profileImageView.isHidden = false
                nickNameLabel.text = message.senderNickname
                
                // 상대가 보낸 사진
                imagePreviewCollectionViewTopConstraint = imagesPreviewCollectionView.topAnchor.constraint(equalTo: nickNameLabel.bottomAnchor, constant: 5)
                imagePreviewCollectionViewLeadingConstraint = imagesPreviewCollectionView.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 5)
                imagePreviewCollectionViewBottomConstraint = imagesPreviewCollectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
                imagePreviewCollectionViewWidthConstraint = imagesPreviewCollectionView.widthAnchor.constraint(equalToConstant: containerWidth)
                imagePreviewCollectionViewHeightConstraint = imagesPreviewCollectionView.heightAnchor.constraint(equalToConstant: contentHeight)
            }
            
            NSLayoutConstraint.activate([
                imagePreviewCollectionViewTopConstraint,
                imagePreviewCollectionViewLeadingConstraint,
                imagePreviewCollectionViewTrailingConstraint,
                imagePreviewCollectionViewBottomConstraint,
                imagePreviewCollectionViewWidthConstraint,
                imagePreviewCollectionViewHeightConstraint,
                
                failedIconImageViewCenterYConstraint,
                failedIconImageViewTrainlingConstraint
            ].compactMap{$0})
            
            imagesPreviewCollectionView.updateCollectionView(images, contentHeight, rows)
        }
    }
    
    private func calculateRowCountWithImage(_ n: Int) -> [Int] {
        guard n > 1 else { return [] }
        
        let maxThreeCount = n / 3
        for i in stride(from: maxThreeCount, to: 0, by: -1) {
            let remaining = n - (3 * i)
            if remaining % 2 == 0 {
                let j = remaining / 2
                return Array(repeating: 3, count: i) + Array(repeating: 2, count: j)
            }
        }
        
        return n % 2 == 0 ? Array(repeating: 2, count: n / 2) : []
    }
}

