//
//  ChatMessageCell.swift
//  OutPick
//
//  Created by 김가윤 on 3/14/25.
//

import Foundation
import UIKit
import Combine

class ChatMessageCell: UICollectionViewCell {
    static let reuseIdentifier = "ChatMessageCell"
    enum ImageUploadOverlayState: Equatable {
        case none
        case uploading(Double)
        case failed
    }

    private var widthConstraint: NSLayoutConstraint?
    private(set) var representedMessageID: String?
    private var thumbnailLoadTask: Task<Void, Never>?
    private var currentHighlightKeyword: String?
    
    protocol ChatMessageCellDelegate: AnyObject {
        func cellDidLongPress(_ cell: ChatMessageCell)
    }
    
    // ⬇️ Combine publishers
    let imageTapSubject = PassthroughSubject<Int?, Never>()
    var imageTapPublisher: AnyPublisher<Int?, Never> { imageTapSubject.eraseToAnyPublisher() }
    let retryTapSubject = PassthroughSubject<Void, Never>()
    var retryTapPublisher: AnyPublisher<Void, Never> { retryTapSubject.eraseToAnyPublisher() }

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
    
    // MARK: - Sent Time Label
    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 10, weight: .regular)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.textAlignment = .left
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
        view.isUserInteractionEnabled = true
        
        return view
    }()

    private let imageUploadOverlayView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        view.isHidden = true
        return view
    }()

    private let imageUploadProgressRing: CircularProgressRingView = {
        let view = CircularProgressRingView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()

    private let imageUploadRetryButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        var config = UIButton.Configuration.filled()
        config.title = "다시 시도"
        config.baseBackgroundColor = UIColor.black.withAlphaComponent(0.55)
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        button.configuration = config
        button.isHidden = true
        return button
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
        label.font = .systemFont(ofSize: 10)
        label.textColor = .black
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let replyPreviewMsgLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 9)
        label.textColor = .black
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let replyPreviewSeparator: UIView = {
        let sep = UIView()
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.backgroundColor = .black
        sep.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return sep
    }()
    
    private lazy var replyPreviewContainer: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [replyPreviewNameLabel, replyPreviewMsgLabel, replyPreviewSeparator])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(10, after: replyPreviewMsgLabel)
        return stack
    }()
    
    // MARK: - Video Badge (▶︎ + duration)
    private let videoBadge: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(white: 0, alpha: 0.55)
        v.layer.cornerRadius = 12
        v.clipsToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true
        return v
    }()
    private let videoIconView: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "play.fill"))
        iv.tintColor = .white
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()
    private let videoDurationLabel: UILabel = {
        let lb = UILabel()
        lb.textColor = .white
        lb.font = .systemFont(ofSize: 12, weight: .semibold)
        lb.text = ""
        lb.translatesAutoresizingMaskIntoConstraints = false
        return lb
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

    private var timeBottomConstraint: NSLayoutConstraint?
    private var timeRightOfHostLeading: NSLayoutConstraint?
    private var timeLeftOfHostTrailing: NSLayoutConstraint?

    private var videoBadgeConstraints: [NSLayoutConstraint] = []
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        contentView.addSubview(profileImageView)
        contentView.addSubview(nickNameLabel)
        contentView.addSubview(bubbleView)
        contentView.addSubview(imagesPreviewCollectionView)
        contentView.addSubview(timeLabel)
        contentView.addSubview(failedIconImageView)
        bubbleView.addSubview(replyPreviewContainer)
        bubbleView.addSubview(messageLabel)
        imagesPreviewCollectionView.addSubview(imageUploadOverlayView)
        imageUploadOverlayView.addSubview(imageUploadProgressRing)
        imageUploadOverlayView.addSubview(imageUploadRetryButton)
        
        messageLabelTopConsraint = messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10)
        NSLayoutConstraint.activate([
            profileImageView.widthAnchor.constraint(equalToConstant: 40),
            profileImageView.heightAnchor.constraint(equalToConstant: 40),
            profileImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            profileImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            
            nickNameLabel.topAnchor.constraint(equalTo: profileImageView.topAnchor),
            nickNameLabel.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 5),
            nickNameLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -8),
            
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

            imageUploadOverlayView.leadingAnchor.constraint(equalTo: imagesPreviewCollectionView.leadingAnchor),
            imageUploadOverlayView.trailingAnchor.constraint(equalTo: imagesPreviewCollectionView.trailingAnchor),
            imageUploadOverlayView.topAnchor.constraint(equalTo: imagesPreviewCollectionView.topAnchor),
            imageUploadOverlayView.bottomAnchor.constraint(equalTo: imagesPreviewCollectionView.bottomAnchor),

            imageUploadProgressRing.centerXAnchor.constraint(equalTo: imageUploadOverlayView.centerXAnchor),
            imageUploadProgressRing.centerYAnchor.constraint(equalTo: imageUploadOverlayView.centerYAnchor),
            imageUploadProgressRing.widthAnchor.constraint(equalToConstant: 46),
            imageUploadProgressRing.heightAnchor.constraint(equalToConstant: 46),

            imageUploadRetryButton.centerXAnchor.constraint(equalTo: imageUploadOverlayView.centerXAnchor),
            imageUploadRetryButton.centerYAnchor.constraint(equalTo: imageUploadOverlayView.centerYAnchor)
        ])
        
        // Time label priorities to avoid truncation
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        
        // Tighten vertical layout to reduce extra spacing
        bubbleView.setContentCompressionResistancePriority(.required, for: .vertical)
        messageLabel.setContentHuggingPriority(.required, for: .vertical)
        // Additional vertical priorities to avoid extra spacing
        messageLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        replyPreviewNameLabel.setContentHuggingPriority(.required, for: .vertical)
        replyPreviewMsgLabel.setContentHuggingPriority(.required, for: .vertical)
        replyPreviewNameLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        replyPreviewMsgLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        replyPreviewContainer.setContentHuggingPriority(.required, for: .vertical)
        
        // 이미지 프리뷰 탭
        let previewTapGR = UITapGestureRecognizer(target: self, action: #selector(handleImagesPreviewTap(_:)))
        previewTapGR.cancelsTouchesInView = false
        imagesPreviewCollectionView.addGestureRecognizer(previewTapGR)
        imagesPreviewCollectionView.isUserInteractionEnabled = true
        imageUploadRetryButton.addTarget(self, action: #selector(handleRetryTap), for: .touchUpInside)
        
        // Set up internal subviews of the video badge (host anchoring is done at configure time)
        videoBadge.addSubview(videoIconView)
        videoBadge.addSubview(videoDurationLabel)
        NSLayoutConstraint.activate([
            videoIconView.leadingAnchor.constraint(equalTo: videoBadge.leadingAnchor, constant: 8),
            videoIconView.centerYAnchor.constraint(equalTo: videoBadge.centerYAnchor),
            videoIconView.widthAnchor.constraint(equalToConstant: 12),
            videoIconView.heightAnchor.constraint(equalToConstant: 12),

            videoDurationLabel.leadingAnchor.constraint(equalTo: videoIconView.trailingAnchor, constant: 6),
            videoDurationLabel.trailingAnchor.constraint(equalTo: videoBadge.trailingAnchor, constant: -8),
            videoDurationLabel.centerYAnchor.constraint(equalTo: videoBadge.centerYAnchor)
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
        thumbnailLoadTask?.cancel()
        thumbnailLoadTask = nil
        representedMessageID = nil
        currentHighlightKeyword = nil
        hideVideoBadge()
        
        messageLabel.attributedText = nil
        messageLabel.textColor = .black
        highlightView?.removeFromSuperview()
        highlightView = nil
        applyImageUploadOverlay(.none)
        
        messageLabel.text = nil
        nickNameLabel.text = nil
        messageLabel.textAlignment = .left
        profileImageView.isHidden = false
        nickNameLabel.isHidden = false
        bubbleView.backgroundColor = UIColor(white: 0.1, alpha: 0.03)
        imagesPreviewCollectionView.isHidden = true

        bubbleView.isHidden = false
        messageLabel.isHidden = false
        replyPreviewSeparator.isHidden = true
        // Clear any previously applied width constraint on bubbleView
        widthConstraint?.isActive = false
        widthConstraint = nil
        
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
        // Reset messageLabel top constraint so that cells without replyPreview don't keep the top-to-reply constraint
        if let top = messageLabelTopConsraint {
            NSLayoutConstraint.deactivate([top])
        }
        messageLabelTopConsraint = messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10)
        messageLabelTopConsraint?.isActive = true
        
        // Reset sent time label and constraints
        timeLabel.text = nil
        timeLabel.isHidden = false
        NSLayoutConstraint.deactivate([timeBottomConstraint, timeRightOfHostLeading, timeLeftOfHostTrailing].compactMap { $0 })
        timeBottomConstraint = nil
        timeRightOfHostLeading = nil
        timeLeftOfHostTrailing = nil
    }
    
    func showVideoBadge(durationText: String?) {
        let host = imagesPreviewCollectionView.isHidden ? bubbleView : imagesPreviewCollectionView
        mountVideoBadge(on: host)
        videoDurationLabel.text = durationText ?? ""
        videoBadge.isHidden = false
    }
    func hideVideoBadge() {
        videoBadge.isHidden = true
        videoDurationLabel.text = ""
    }

    /// configure 재호출(reconfigure/async thumbnail apply) 시 이전 동적 제약 누적을 막는다.
    private func resetDynamicLayoutConstraintsForReconfigure() {
        widthConstraint?.isActive = false
        widthConstraint = nil

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
        ].compactMap { $0 })

        bubbleViewLeadingConstraint = nil
        bubbleViewTrailingConstraint = nil
        bubbleViewTopConstraint = nil
        bubbleViewBottomConstraint = nil

        imagePreviewCollectionViewTopConstraint = nil
        imagePreviewCollectionViewLeadingConstraint = nil
        imagePreviewCollectionViewTrailingConstraint = nil
        imagePreviewCollectionViewBottomConstraint = nil
        imagePreviewCollectionViewWidthConstraint = nil
        imagePreviewCollectionViewHeightConstraint = nil

        failedIconImageViewCenterYConstraint = nil
        failedIconImageViewTrainlingConstraint = nil
        failedIconImageView.isHidden = true
    }
    
    func configureWithMessage(with message: ChatMessage/*, originalPreviewProvider: (() -> (String, String)?)?*/) {
        thumbnailLoadTask?.cancel()
        thumbnailLoadTask = nil
        representedMessageID = message.ID
        resetDynamicLayoutConstraintsForReconfigure()
        // Explicitly reset/hide/unhide and clear any previous width constraint
        bubbleView.isHidden = false
        messageLabel.attributedText = nil
        messageLabel.isHidden = true ? false : false // ensure visible (no-op but explicit)
        messageLabel.isHidden = false
        imagesPreviewCollectionView.isHidden = true

        // Compute isMine once
        let isMine = (LoginManager.shared.currentUserProfile?.nickname ?? "") == message.senderNickname

        if message.isDeleted {
            messageLabel.text = "삭제된 메시지입니다."
            messageLabel.textColor = UIColor.black.withAlphaComponent(0.4)
        } else {
            messageLabel.text = message.msg
        }
        imagesPreviewCollectionView.isHidden = true
        
        let containerWidth = UIScreen.main.bounds.width * 0.7
        
        if isMine {
            // 본인이 보낸 메시지
            bubbleView.backgroundColor = .systemBlue
            profileImageView.isHidden = true
            nickNameLabel.isHidden = true
            
            // 기본 제약조건 업데이트
            bubbleViewLeadingConstraint = bubbleView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 20)
            bubbleViewTrailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8)
            bubbleViewTopConstraint = bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor)
            bubbleViewBottomConstraint = bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            widthConstraint = bubbleView.widthAnchor.constraint(lessThanOrEqualToConstant: containerWidth)
            widthConstraint?.isActive = true
            
            failedIconImageView.isHidden = true
            if message.isFailed {
                failedIconImageView.isHidden = false
                
                failedIconImageViewCenterYConstraint = failedIconImageView.centerYAnchor.constraint(equalTo: bubbleView.centerYAnchor)
                failedIconImageViewTrainlingConstraint = failedIconImageView.trailingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: -2)
            }
            
        } else {
            // 상대방이 보낸 메시지
            nickNameLabel.text = message.senderNickname
            bubbleView.backgroundColor = /*UIColor(white: 0.1, alpha: 0.03)*/.secondarySystemBackground
            
            // 기본 제약조건으로 복원
            bubbleViewLeadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 5)
            bubbleViewTrailingConstraint = bubbleView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -10)
            bubbleViewTopConstraint = bubbleView.topAnchor.constraint(equalTo: nickNameLabel.bottomAnchor, constant: 5)
            bubbleViewBottomConstraint = bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            widthConstraint = bubbleView.widthAnchor.constraint(lessThanOrEqualToConstant: containerWidth)
            widthConstraint?.isActive = true
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
        
        // 답장 프리뷰 처리
        if message.isDeleted {
            // 🔹 원본 메시지가 삭제된 경우: 프리뷰를 아예 숨기고 기본 레이아웃로 복귀
            replyPreviewContainer.isHidden = true
            replyPreviewSeparator.isHidden = true
            NSLayoutConstraint.deactivate([messageLabelTopConsraint!])
            messageLabelTopConsraint = messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10)
            NSLayoutConstraint.activate([ messageLabelTopConsraint! ])
        } else if let replyMessage = message.replyPreview {
            // 🔹 답장 프리뷰 표시 (참조된 메시지가 삭제되었으면 플레이스홀더만)
            replyPreviewContainer.isHidden = false
            replyPreviewSeparator.isHidden = false
            replyPreviewNameLabel.text = replyMessage.sender
            if replyMessage.isDeleted {
                replyPreviewMsgLabel.text = "삭제된 메시지입니다."
            } else {
                replyPreviewMsgLabel.text = replyMessage.text
            }
            NSLayoutConstraint.deactivate([messageLabelTopConsraint!])
            messageLabelTopConsraint = messageLabel.topAnchor.constraint(equalTo: replyPreviewContainer.bottomAnchor, constant: 3)
            NSLayoutConstraint.activate([ messageLabelTopConsraint! ])
        } else {
            // 🔹 프리뷰 없음
            replyPreviewContainer.isHidden = true
            replyPreviewSeparator.isHidden = true
            NSLayoutConstraint.deactivate([messageLabelTopConsraint!])
            messageLabelTopConsraint = messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10)
            NSLayoutConstraint.activate([ messageLabelTopConsraint! ])
        }
        
        // 보낸 시간 (실패 메시지는 숨김)
        if message.isFailed {
            timeLabel.isHidden = true
        } else {
            timeLabel.isHidden = false
            timeLabel.text = formattedTime(message.sentAt)
            mountTimeLabel(on: bubbleView, isMine: isMine)
        }
        
        self.setNeedsLayout()
        self.layoutIfNeeded()
    }
    
    func configureWithImage(
        with message: ChatMessage,
        images: [UIImage],
        thumbnailLoader: ((ChatMessage) async -> [UIImage])? = nil
    ) {
        thumbnailLoadTask?.cancel()
        thumbnailLoadTask = nil
        representedMessageID = message.ID
        resetDynamicLayoutConstraintsForReconfigure()
        messageLabel.attributedText = nil
        
        // 삭제된 메시지를 이미지가 아니라, "삭제된 메시지입니다."로 표시
        if message.isDeleted {
            bubbleView.isHidden = false
            messageLabel.isHidden = false
            imagesPreviewCollectionView.isHidden = true

            messageLabel.text = "삭제된 메시지입니다."
            messageLabel.textColor = UIColor.black.withAlphaComponent(0.4)

            NSLayoutConstraint.deactivate([
                imagePreviewCollectionViewTopConstraint,
                imagePreviewCollectionViewLeadingConstraint,
                imagePreviewCollectionViewTrailingConstraint,
                imagePreviewCollectionViewBottomConstraint,
                imagePreviewCollectionViewWidthConstraint,
                imagePreviewCollectionViewHeightConstraint
            ].compactMap { $0 })
            imagePreviewCollectionViewTopConstraint = nil
            imagePreviewCollectionViewLeadingConstraint = nil
            imagePreviewCollectionViewTrailingConstraint = nil
            imagePreviewCollectionViewBottomConstraint = nil
            imagePreviewCollectionViewWidthConstraint = nil
            imagePreviewCollectionViewHeightConstraint = nil

            let containerWidth = UIScreen.main.bounds.width * 0.7

            let isMine = (LoginManager.shared.currentUserProfile?.nickname ?? "") == message.senderNickname
            if isMine {
                // 본인이 보낸(삭제된) 메시지로 표시
                bubbleView.backgroundColor = .systemBlue
                profileImageView.isHidden = true
                nickNameLabel.isHidden = true

                bubbleViewLeadingConstraint = bubbleView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 20)
                bubbleViewTrailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8)
                bubbleViewTopConstraint = bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor)
                bubbleViewBottomConstraint = bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            } else {
                // 상대방이 보낸(삭제된) 메시지로 표시
                nickNameLabel.text = message.senderNickname
                bubbleView.backgroundColor = .secondarySystemBackground

                bubbleViewLeadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 5)
                bubbleViewTrailingConstraint = bubbleView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -10)
                bubbleViewTopConstraint = bubbleView.topAnchor.constraint(equalTo: nickNameLabel.bottomAnchor, constant: 5)
                bubbleViewBottomConstraint = bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            }

            widthConstraint = bubbleView.widthAnchor.constraint(lessThanOrEqualToConstant: containerWidth)
            widthConstraint?.isActive = true

            // 실패 아이콘은 숨김
            failedIconImageView.isHidden = true
            failedIconImageViewCenterYConstraint?.isActive = false
            failedIconImageViewTrainlingConstraint?.isActive = false
            failedIconImageViewCenterYConstraint = nil
            failedIconImageViewTrainlingConstraint = nil

            // 답장 프리뷰는 숨김, 메시지 라벨의 top을 버블 top으로
            replyPreviewContainer.isHidden = true
            replyPreviewSeparator.isHidden = true
            if let top = messageLabelTopConsraint { NSLayoutConstraint.deactivate([top]) }
            messageLabelTopConsraint = messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10)
            messageLabelTopConsraint?.isActive = true

            NSLayoutConstraint.activate([
                bubbleViewLeadingConstraint,
                bubbleViewTrailingConstraint,
                bubbleViewTopConstraint,
                bubbleViewBottomConstraint
            ].compactMap { $0 })

            // Sent time for deleted-as-text case (실패 메시지는 숨김)
            if message.isFailed {
                timeLabel.isHidden = true
            } else {
                timeLabel.isHidden = false
                timeLabel.text = formattedTime(message.sentAt)
                mountTimeLabel(on: bubbleView, isMine: isMine)
            }

            self.setNeedsLayout()
            self.layoutIfNeeded()
            return
        }

        bubbleView.isHidden = true
        messageLabel.isHidden = true
        imagesPreviewCollectionView.isHidden = false
        
        if let nickName = LoginManager.shared.currentUserProfile?.nickname {
            let containerWidth = contentView.frame.width * 0.7
            let rows = calculateRowCountWithImage(message.attachments.count)
            
            var contentHeight: CGFloat {
                if message.attachments.count == 1 {
                    return contentView.frame.width * 0.7
                } else {
                    return rows.reduce(0) { $0 + (containerWidth / CGFloat($1)) }
                }
            }
            
            print("내 닉네임: \(nickName)")
            print("보낸 사람: \(message.senderNickname)")
            
            let isMine = nickName == message.senderNickname
            if isMine {
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

            // 보낸 시간 (실패 메시지는 숨김)
            if message.isFailed {
                timeLabel.isHidden = true
            } else {
                timeLabel.isHidden = false
                timeLabel.text = formattedTime(message.sentAt)
                mountTimeLabel(on: imagesPreviewCollectionView, isMine: isMine)
            }

            if let firstVideo = message.attachments.first, firstVideo.type == .video {
                if let dur = firstVideo.duration {
                    showVideoBadge(durationText: formatDuration(dur))
                } else {
                    hideVideoBadge()
                }
            } else {
                hideVideoBadge()
            }
        }

        guard images.isEmpty,
              let thumbnailLoader,
              !message.attachments.isEmpty else { return }

        let messageID = message.ID
        thumbnailLoadTask = Task { [weak self] in
            guard let self else { return }
            let loadedImages = await thumbnailLoader(message)
            if Task.isCancelled { return }

            await MainActor.run {
                guard self.representedMessageID == messageID else { return }
                self.thumbnailLoadTask = nil
                self.configureWithImage(with: message, images: loadedImages)
                self.highlightKeyword(self.currentHighlightKeyword)
            }
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
        currentHighlightKeyword = keyword
        let baseText = messageLabel.text ?? messageLabel.attributedText?.string ?? ""
        guard !baseText.isEmpty else {
            messageLabel.attributedText = nil
            messageLabel.text = nil
            setHightlightedOverlay(false)
            return
        }

        guard let keyword = keyword, !keyword.isEmpty else {
            messageLabel.attributedText = nil
            messageLabel.text = baseText
            setHightlightedOverlay(false)
            return
        }

        var baseAttributes: [NSAttributedString.Key: Any] = [:]
        baseAttributes[.font] = messageLabel.font as Any
        baseAttributes[.foregroundColor] = messageLabel.textColor as Any

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = messageLabel.textAlignment
        paragraphStyle.lineBreakMode = messageLabel.lineBreakMode
        baseAttributes[.paragraphStyle] = paragraphStyle

        let attributed = NSMutableAttributedString(string: baseText, attributes: baseAttributes)
        let range = (baseText as NSString).range(of: keyword, options: .caseInsensitive)
        if range.location != NSNotFound {
            attributed.addAttribute(.backgroundColor, value: UIColor.yellow, range: range)
            attributed.addAttribute(.foregroundColor, value: UIColor.black, range: range)
        }
        messageLabel.text = nil
        messageLabel.attributedText = attributed
        setHightlightedOverlay(range.location != NSNotFound)
    }
    
    private func makeSeparator() -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 0.5 / UIScreen.main.scale).isActive = true
        return view
    }

    @objc private func handleImagesPreviewTap(_ gr: UITapGestureRecognizer) {
        let point = gr.location(in: imagesPreviewCollectionView)
        let tappedIndex = imagesPreviewCollectionView.index(at: point)
        imageTapSubject.send(tappedIndex)
    }

    @objc private func handleRetryTap() {
        retryTapSubject.send(())
    }

    func currentPreviewImages() -> [UIImage] {
        imagesPreviewCollectionView.currentImages()
    }

    func applyImageUploadOverlay(_ state: ImageUploadOverlayState) {
        switch state {
        case .none:
            imageUploadOverlayView.isHidden = true
            imageUploadProgressRing.isHidden = true
            imageUploadRetryButton.isHidden = true
            imageUploadProgressRing.setProgress(0)
        case .uploading(let progress):
            imageUploadOverlayView.isHidden = false
            imageUploadOverlayView.backgroundColor = UIColor.black.withAlphaComponent(0.36)
            imageUploadProgressRing.isHidden = false
            imageUploadRetryButton.isHidden = true
            imageUploadProgressRing.setProgress(CGFloat(max(0, min(1, progress))))
        case .failed:
            imageUploadOverlayView.isHidden = false
            imageUploadOverlayView.backgroundColor = UIColor.black.withAlphaComponent(0.42)
            imageUploadProgressRing.isHidden = true
            imageUploadRetryButton.isHidden = false
        }
    }

    // MARK: - Time Label Helpers
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale.current
        return f
    }()

    private func formattedTime(_ date: Date?) -> String {
        guard let d = date else { return "" }
        return ChatMessageCell.timeFormatter.string(from: d)
    }

    private func mountTimeLabel(on host: UIView, isMine: Bool) {
        NSLayoutConstraint.deactivate([timeBottomConstraint, timeRightOfHostLeading, timeLeftOfHostTrailing].compactMap { $0 })
        timeBottomConstraint = timeLabel.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        if isMine {
            // 내 메시지(오른쪽 버블): 시간은 버블 '왼쪽' 바깥에
            timeLeftOfHostTrailing = timeLabel.trailingAnchor.constraint(equalTo: host.leadingAnchor, constant: -4)
            timeRightOfHostLeading = nil
            timeLabel.textAlignment = .right
        } else {
            // 상대 메시지(왼쪽 버블): 시간은 버블 '오른쪽' 바깥에
            timeRightOfHostLeading = timeLabel.leadingAnchor.constraint(equalTo: host.trailingAnchor, constant: 4)
            timeLeftOfHostTrailing = nil
            timeLabel.textAlignment = .left
        }
        // Activate
        NSLayoutConstraint.activate([timeBottomConstraint, timeRightOfHostLeading, timeLeftOfHostTrailing].compactMap { $0 })
        // Ensure label is on top visually
        contentView.bringSubviewToFront(timeLabel)
    }

    /// 비디오 재생 버튼 + 재생 시간 표시
    private func mountVideoBadge(on host: UIView) {
        if videoBadge.superview !== host {
            videoBadge.removeFromSuperview()
            host.addSubview(videoBadge)
        }
        NSLayoutConstraint.deactivate(videoBadgeConstraints)
        videoBadge.translatesAutoresizingMaskIntoConstraints = false
        videoBadgeConstraints = [
            videoBadge.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            videoBadge.centerYAnchor.constraint(equalTo: host.centerYAnchor),
            videoBadge.heightAnchor.constraint(equalToConstant: 24)
        ]
        NSLayoutConstraint.activate(videoBadgeConstraints)
        host.bringSubviewToFront(videoBadge)
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(round(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
}

private final class CircularProgressRingView: UIView {
    private let trackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = UIColor.black.withAlphaComponent(0.24)
        layer.cornerRadius = 23

        trackLayer.fillColor = UIColor.clear.cgColor
        trackLayer.strokeColor = UIColor.white.withAlphaComponent(0.25).cgColor
        trackLayer.lineWidth = 4
        layer.addSublayer(trackLayer)

        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.strokeColor = UIColor.white.cgColor
        progressLayer.lineWidth = 4
        progressLayer.lineCap = .round
        progressLayer.strokeEnd = 0
        layer.addSublayer(progressLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset: CGFloat = 6
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let start = -CGFloat.pi / 2
        let end = start + (CGFloat.pi * 2)
        let path = UIBezierPath(arcCenter: CGPoint(x: rect.midX, y: rect.midY),
                                radius: rect.width / 2,
                                startAngle: start,
                                endAngle: end,
                                clockwise: true)
        trackLayer.frame = bounds
        progressLayer.frame = bounds
        trackLayer.path = path.cgPath
        progressLayer.path = path.cgPath
    }

    func setProgress(_ progress: CGFloat) {
        progressLayer.strokeEnd = max(0, min(1, progress))
    }
}
