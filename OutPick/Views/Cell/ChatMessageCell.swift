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
        view.backgroundColor = .lightGray
        return view
    }()
    
    private var bubbleViewTrailingConstraint: NSLayoutConstraint?
    private var bubbleViewLeadingConstraint: NSLayoutConstraint?
    private var bubbleViewTopConstraint: NSLayoutConstraint?
    
    private var imagePreviewCollectionViewTopConstraint: NSLayoutConstraint?
    private var imagePreviewCollectionViewLeadingConstraint: NSLayoutConstraint?
    private var imagePreviewCollectionViewTrailingConstraint: NSLayoutConstraint?
    private var imagePreviewCollectionViewWidthConstraint: NSLayoutConstraint?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        contentView.backgroundColor = .black
        
        contentView.addSubview(profileImageView)
        contentView.addSubview(nickNameLabel)
        contentView.addSubview(bubbleView)
        contentView.addSubview(imagesPreviewCollectionView)
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
            messageLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -8),
        ])
        
        // 기본 bubbleView 제약조건 설정
        bubbleViewLeadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 5)
        bubbleViewTrailingConstraint = bubbleView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20)
        bubbleViewTopConstraint = bubbleView.topAnchor.constraint(equalTo: nickNameLabel.bottomAnchor, constant: 5)
        //
        //        imagePreviewCollectionViewTopConstraint = imagesPreviewCollectionView.topAnchor.constraint(equalTo: self.bottomAnchor, constant: 8)
        //        imagePreviewCollectionViewLeadingConstraint = imagesPreviewCollectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8)
        //        imagePreviewCollectionViewWidthConstraint = imagesPreviewCollectionView.widthAnchor.constraint(equalToConstant: contentView.frame.width * 0.7)
        //
        NSLayoutConstraint.activate([
            bubbleViewLeadingConstraint,
            bubbleViewTrailingConstraint,
            bubbleViewTopConstraint,
            //
            //            imagePreviewCollectionViewTopConstraint,
            //            imagePreviewCollectionViewLeadingConstraint,
            //            imagePreviewCollectionViewWidthConstraint
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
        imagesPreviewCollectionView.isHidden = true
        
        NSLayoutConstraint.deactivate([
            bubbleViewLeadingConstraint,
            bubbleViewTrailingConstraint,
            bubbleViewTopConstraint,
            
            imagePreviewCollectionViewTopConstraint,
            imagePreviewCollectionViewLeadingConstraint,
            imagePreviewCollectionViewTrailingConstraint,
            imagePreviewCollectionViewWidthConstraint
        ].compactMap{ $0 })
    }
    
    func configureWithMessage(with message: ChatMessage) {
        messageLabel.text = message.msg
        imagesPreviewCollectionView.isHidden = true
        
        if let nickName = UserProfile.shared.nickname,
           nickName == message.senderNickname {
            // 본인이 보낸 메시지
            bubbleView.backgroundColor = .systemBlue
            profileImageView.isHidden = true
            nickNameLabel.isHidden = true
            messageLabel.textAlignment = .right
            
            // 기본 제약조건 업데이트
            bubbleViewLeadingConstraint = bubbleView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 20)
            bubbleViewTrailingConstraint?.constant = -8
            bubbleViewTopConstraint?.constant = 8
        } else {
            // 상대방이 보낸 메시지
            nickNameLabel.text = message.senderNickname
            bubbleView.backgroundColor = UIColor(white: 0.1, alpha: 0.03)
            
            // 기본 제약조건으로 복원
            bubbleViewLeadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 5)
            bubbleViewTrailingConstraint?.constant = -20
            bubbleViewTopConstraint?.constant = 5
        }
        
        // 제약조건 활성화
        NSLayoutConstraint.activate([
            bubbleViewLeadingConstraint,
            bubbleViewTrailingConstraint,
            bubbleViewTopConstraint,
        ].compactMap{ $0 })
        
        self.setNeedsLayout()
        self.layoutIfNeeded()
    }
    
    func configureWithImage(with message: ChatMessage) {
        profileImageView.isHidden = true
        bubbleView.isHidden = true
        messageLabel.isHidden = true
        imagesPreviewCollectionView.isHidden = false
        
        if let attachments = message.attachments,
           let nickName = UserProfile.shared.nickname {
            
            let images = attachments.compactMap {
                if let imageData = $0.fileData {
                    return UIImage(data: imageData)
                }
                return nil
            }
            
            let containerWidth = contentView.frame.width * 0.7
            
            // 이미지 개수에 따른 크기 조정
            let height: CGFloat
            if images.count == 1 {
                height = containerWidth
            } else {
                let rows = ceil(Double(images.count) / 3.0)
                height = (containerWidth / 3.0) * rows
            }
            
            if nickName == message.senderNickname {
                // 본인이 보낸 사진
                NSLayoutConstraint.activate([
                    imagesPreviewCollectionView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
                    imagesPreviewCollectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
                    imagesPreviewCollectionView.widthAnchor.constraint(equalToConstant: containerWidth),
                    imagesPreviewCollectionView.heightAnchor.constraint(equalToConstant: height),
                    imagesPreviewCollectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
                ])
            } else {
                // 상대가 보낸 사진
                NSLayoutConstraint.activate([
                    imagesPreviewCollectionView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
                    imagesPreviewCollectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
                    imagesPreviewCollectionView.widthAnchor.constraint(equalToConstant: containerWidth),
                    imagesPreviewCollectionView.heightAnchor.constraint(equalToConstant: height),
                    imagesPreviewCollectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
                ])
            }
            
            imagesPreviewCollectionView.updateCollectionView(with: images)
        }
    }
}
 
