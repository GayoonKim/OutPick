//
//  ChatMessageCell.swift
//  OutPick
//
//  Created by 김가윤 on 3/14/25.
//

import Foundation
import UIKit


class ChatMessageCell: UICollectionViewCell {
    static let reuseIdentifier = "ChatMessageCell"
    private var widthConstraint: NSLayoutConstraint?
    
    protocol ChatMessageCellDelegate: AnyObject {
        func cellDidLongPress(_ cell: ChatMessageCell)
    }
    
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
        label.lineBreakMode = .byCharWrapping
        label.backgroundColor = .clear
        label.textColor = .black
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false

        return label
    }()
    
    private let bubbleView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 12
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    var referenceView: UIView {
        bubbleView.isHidden ? imagesPreviewCollectionView : bubbleView
    }
    
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
    
    private let replyPreviewNameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 10, weight: .heavy)
        label.textColor = .black
        return label
    }()

    private let replyPreviewMsgLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 9, weight: .medium)
        label.textColor = .black
        label.numberOfLines = 1
        return label
    }()
    
    private lazy var replyPreviewContainer: UIStackView = {
        let separator = UIView()
        separator.backgroundColor = .black
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        
        let stack = UIStackView(arrangedSubviews: [replyPreviewNameLabel, replyPreviewMsgLabel, separator])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isHidden = true
        stack.setCustomSpacing(10, after: replyPreviewMsgLabel)
        return stack
    }()
    
    private var highlightView: UIView?

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
    
    private var messageLabelTopConsraint: NSLayoutConstraint?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        contentView.addSubview(profileImageView)
        contentView.addSubview(nickNameLabel)
        contentView.addSubview(bubbleView)
        contentView.addSubview(imagesPreviewCollectionView)
        contentView.addSubview(failedIconImageView)
        bubbleView.addSubview(replyPreviewContainer)
        bubbleView.addSubview(messageLabel)
        
        messageLabelTopConsraint = messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10)
        NSLayoutConstraint.activate([
            profileImageView.widthAnchor.constraint(equalToConstant: 40),
            profileImageView.heightAnchor.constraint(equalToConstant: 40),
            profileImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            profileImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            
            nickNameLabel.topAnchor.constraint(equalTo: profileImageView.topAnchor),
            nickNameLabel.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 5),
            
            replyPreviewContainer.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10),
            replyPreviewContainer.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 10),
            replyPreviewContainer.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -10),
            
            messageLabelTopConsraint!,
            messageLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 10),
            messageLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -10),
            messageLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -10),
            messageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: UIScreen.main.bounds.width * 0.7),
                       
            
            failedIconImageView.widthAnchor.constraint(equalToConstant: 20),
            failedIconImageView.heightAnchor.constraint(equalToConstant: 20),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        messageLabel.attributedText = nil
        highlightView?.removeFromSuperview()
        highlightView = nil
        
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
        
        failedIconImageView.isHidden = true
        failedIconImageViewCenterYConstraint?.isActive = false
        failedIconImageViewTrainlingConstraint?.isActive = false
        failedIconImageViewCenterYConstraint = nil
        failedIconImageViewTrainlingConstraint = nil
        
        replyPreviewContainer.isHidden = true
        replyPreviewNameLabel.text = nil
        replyPreviewMsgLabel.text = nil
    }
    
    func configureWithMessage(with message: ChatMessage/*, originalPreviewProvider: (() -> (String, String)?)?*/) {
        messageLabel.text = message.msg
        imagesPreviewCollectionView.isHidden = true
        
        let containerWidth = UIScreen.main.bounds.width * 0.7
        
        if let nickName = LoginManager.shared.currentUserProfile?.nickname,
           nickName == message.senderNickname {
            // 본인이 보낸 메시지
            bubbleView.backgroundColor = .systemBlue
            profileImageView.isHidden = true
            nickNameLabel.isHidden = true
            
            // 기본 제약조건 업데이트
            bubbleViewLeadingConstraint = bubbleView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 20)
            bubbleViewTrailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8)
            bubbleViewTopConstraint = bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor)
            bubbleViewBottomConstraint = bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            bubbleView.widthAnchor.constraint(lessThanOrEqualToConstant: containerWidth).isActive = true
            
            failedIconImageView.isHidden = true
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
            bubbleViewTrailingConstraint = bubbleView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -10)
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
        
        if let replyMessage = message.replyPreview {
            replyPreviewContainer.isHidden = false
            replyPreviewNameLabel.text = replyMessage.sender
            
            if replyMessage.isDeleted {
                replyPreviewMsgLabel.text = "삭제된 메시지입니다."
                replyPreviewMsgLabel.backgroundColor = .secondarySystemBackground
            } else {
                replyPreviewMsgLabel.text = replyMessage.text
            }
            
            NSLayoutConstraint.deactivate([messageLabelTopConsraint!])
            messageLabelTopConsraint = messageLabel.topAnchor.constraint(equalTo: replyPreviewContainer.bottomAnchor, constant: 3)
            NSLayoutConstraint.activate([ messageLabelTopConsraint! ])
        } else {
            replyPreviewContainer.isHidden = true
        }
        
        self.setNeedsLayout()
        self.layoutIfNeeded()
    }

    func configureWithImage(with message: ChatMessage) {
        bubbleView.isHidden = true
        messageLabel.isHidden = true
        imagesPreviewCollectionView.isHidden = false
        
        if let nickName = LoginManager.shared.currentUserProfile?.nickname {
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
            
            print("내 닉네임: \(nickName)")
            print("보낸 사람: \(message.senderNickname)")
            
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
    
    func setHightlightedOverlay(_ highlighted: Bool) {
        if highlighted {
            if highlightView == nil {
                let overayView = UIView()
                overayView.translatesAutoresizingMaskIntoConstraints = false
                overayView.backgroundColor = UIColor.black.withAlphaComponent(0.1)
                overayView.layer.cornerRadius = bubbleView.layer.cornerRadius
                overayView.isUserInteractionEnabled = false
                bubbleView.addSubview(overayView)
                highlightView = overayView
                
                NSLayoutConstraint.activate([
                    overayView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor),
                    overayView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor),
                    overayView.topAnchor.constraint(equalTo: bubbleView.topAnchor),
                    overayView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor)
                ])
            }
        } else {
            highlightView?.removeFromSuperview()
            highlightView = nil
        }
    }

    func shakeHorizontally(duration: CFTimeInterval = 0.5, repeatCount: Float = 1) {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.duration = duration
        animation.values = [0, 8, -8, 6, -6, 4, -4, 0] // 흔들림 강도
        animation.repeatCount = repeatCount
        layer.add(animation, forKey: "shake")
    }
    
    func highlightKeyword(_ keyword: String?) {
        guard let text = messageLabel.text else { return }

        if let keyword = keyword, !keyword.isEmpty {
            let attributed = NSMutableAttributedString(string: text)
            let range = (text as NSString).range(of: keyword, options: .caseInsensitive)
            if range.location != NSNotFound {
                attributed.addAttribute(.backgroundColor, value: UIColor.yellow, range: range)
                attributed.addAttribute(.foregroundColor, value: UIColor.black, range: range)
            }
            messageLabel.attributedText = attributed
            setHightlightedOverlay(true) // overlay도 제거
        } else {
            messageLabel.attributedText = NSAttributedString(string: text)
            setHightlightedOverlay(false) // overlay도 제거
        }
    }
    
    private func makeSeparator() -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 0.5 / UIScreen.main.scale).isActive = true
        return view
    }
}

