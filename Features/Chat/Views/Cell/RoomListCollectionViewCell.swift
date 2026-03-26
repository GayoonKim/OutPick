//
//  RoomListCollectionViewCell.swift
//  OutPick
//
//  Created by 김가윤 on 10/15/24.
//

import UIKit

class RoomListCollectionViewCell: UICollectionViewCell {
    static let identifier = "RoomListCollectionViewCell"
    private let roomImageManager: RoomImageManaging = RoomImageService.shared
    private var imageLoadTask: Task<Void, Never>?
    private var representedImagePath: String?

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
        stackView.spacing = 6
        stackView.alignment = .fill
        stackView.distribution = .fill
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
    
    override func prepareForReuse() {
        super.prepareForReuse()
        imageLoadTask?.cancel()
        imageLoadTask = nil
        representedImagePath = nil
        applyDefaultRoomImage()
        roomNameLabel.text = nil
        roomDescriptionLabel.text = nil
        previewStackView.arrangedSubviews.forEach { view in
            previewStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = layoutAttributes.copy() as! UICollectionViewLayoutAttributes
        setNeedsLayout()
        layoutIfNeeded()

        let targetSize = CGSize(
            width: attributes.size.width,
            height: UIView.layoutFittingCompressedSize.height
        )

        let fittedSize = contentView.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )

        attributes.size.height = ceil(fittedSize.height)
        return attributes
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

            previewStackView.topAnchor.constraint(equalTo: roomDescriptionLabel.bottomAnchor, constant: 10),
            previewStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            previewStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            previewStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }
    
    func configure(room: ChatRoom, messages: [ChatMessage]) {
        imageLoadTask?.cancel()
        imageLoadTask = nil
        representedImagePath = room.coverImagePath
        applyDefaultRoomImage()
        roomImageView.layer.cornerRadius = 8
        roomImageView.clipsToBounds = true

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

        loadRoomImageIfNeeded(for: room)
    }
    
    func configureJoined(room: ChatRoom, message: ChatMessage) {
        
    }

    private func loadRoomImageIfNeeded(for room: ChatRoom) {
        guard let imagePath = room.coverImagePath, !imagePath.isEmpty else { return }

        let roomImageManager = self.roomImageManager
        imageLoadTask = Task { [weak self] in
            guard let self else { return }

            do {
                if let cached = await roomImageManager.cachedImage(for: imagePath) {
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard self.representedImagePath == imagePath else { return }
                        self.roomImageView.image = cached
                    }
                    return
                }

                let image = try await roomImageManager.loadImage(
                    for: imagePath,
                    maxBytes: 3 * 1024 * 1024
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.representedImagePath == imagePath else { return }
                    self.roomImageView.image = image
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.representedImagePath == imagePath else { return }
                    self.applyDefaultRoomImage()
                }
            }
        }
    }

    private func applyDefaultRoomImage() {
        roomImageView.image = UIImage(named: "Default_Profile")
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
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
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
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        return label
    }()
    
    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 10, weight: .regular)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.textAlignment = .left
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
        separator.backgroundColor = .white
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        
        let contentStack = UIStackView(arrangedSubviews: [replyPreviewNameLabel, replyPreviewMsgLabel, separator])
        contentStack.axis = .vertical
        contentStack.spacing = 4
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        
        let container = UIView()
        container.backgroundColor = .black
        container.layer.cornerRadius = 8
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layoutMargins = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        container.isHidden = true
        
        container.addSubview(contentStack)
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.layoutMargins = .zero
        
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: container.layoutMarginsGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: container.layoutMarginsGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: container.layoutMarginsGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: container.layoutMarginsGuide.bottomAnchor)
        ])
        
        let stack = UIStackView(arrangedSubviews: [container])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isHidden = true
        
        return stack
    }()
    
    private var leadingConstraint: NSLayoutConstraint?
    private var trailingConstraint: NSLayoutConstraint?
    private var bubbleTopToNickname: NSLayoutConstraint?
    private var bubbleTopToTop: NSLayoutConstraint?
    private var messageTopToBubbleTop: NSLayoutConstraint?
    private var messageTopToReplyBottom: NSLayoutConstraint?
    private var messageCenterYConstraint: NSLayoutConstraint?
    private var timeLeftOfBubbleTrailing: NSLayoutConstraint?
    private var timeRightOfBubbleLeading: NSLayoutConstraint?

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
        bubbleView.addSubview(replyPreviewContainer)
        bubbleView.addSubview(timeLabel)
        
        profileImageView.translatesAutoresizingMaskIntoConstraints = false
        nicknameLabel.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        
        
        bubbleTopToNickname = bubbleView.topAnchor.constraint(equalTo: nicknameLabel.bottomAnchor, constant: 5)
        bubbleTopToTop = bubbleView.topAnchor.constraint(equalTo: topAnchor, constant: 10)

        bubbleTopToNickname?.isActive = true // 기본은 상대방 메시지 기준
        NSLayoutConstraint.activate([
            profileImageView.heightAnchor.constraint(equalToConstant: 36),
            profileImageView.widthAnchor.constraint(equalToConstant: 36),
            profileImageView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            profileImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),

            nicknameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            nicknameLabel.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 5),
            
            bubbleView.widthAnchor.constraint(lessThanOrEqualTo: self.widthAnchor, multiplier: 0.7),
            bubbleView.heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
            
            replyPreviewContainer.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10),
            replyPreviewContainer.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 10),
            replyPreviewContainer.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -10),
            
            // Time label aligned to bubble bottom
            timeLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor),

            // Message label inside bubble, above its bottom
            messageLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 8),
            messageLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -8),
            messageLabel.bottomAnchor.constraint(lessThanOrEqualTo: bubbleView.bottomAnchor, constant: -8),
            
            bubbleView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
        
        messageTopToBubbleTop = messageLabel.topAnchor.constraint(greaterThanOrEqualTo: bubbleView.topAnchor, constant: 8)
        messageTopToReplyBottom = messageLabel.topAnchor.constraint(equalTo: replyPreviewContainer.bottomAnchor, constant: 3)
        messageTopToBubbleTop?.isActive = true // 기본: 프리뷰 없음

        // 메시지 레이블을 버블 중앙에 배치하는 제약조건 (기본 활성화)
        messageCenterYConstraint = messageLabel.centerYAnchor.constraint(equalTo: bubbleView.centerYAnchor)
        messageCenterYConstraint?.isActive = true
        
        // 미리 leading/trailing 제약 저장
        leadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 5)
        trailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10)

        // time label outside the bubble, baseline-aligned
        timeRightOfBubbleLeading = timeLabel.leadingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: 4)   // 상대 메시지(좌측 버블) 기본
        timeLeftOfBubbleTrailing = timeLabel.trailingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: -4)  // 내 메시지(우측 버블)
        // 기본은 상대방 메시지 기준(버블 오른쪽에 시간)
        timeRightOfBubbleLeading?.isActive = true

        // Make time label resist compression and hug contents
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }
    
    func configure(with message: ChatMessage, isMine: Bool) {
        // 기본 본문/닉네임 세팅
        nicknameLabel.text = message.senderNickname
        if let text = message.msg, !text.isEmpty {
            messageLabel.text = text
        } else if !message.attachments.isEmpty {
            let imageCount = message.attachments.filter { $0.type == .image }.count
            let videoCount = message.attachments.filter { $0.type == .video }.count

            if videoCount > 0 && imageCount == 0 {
                messageLabel.text = videoCount == 1 ? "동영상 1개" : "동영상 \(videoCount)개"
            } else if imageCount > 0 && videoCount == 0 {
                messageLabel.text = imageCount == 1 ? "사진 1장" : "사진 \(imageCount)장"
            } else if imageCount > 0 && videoCount > 0 {
                messageLabel.text = "사진 \(imageCount)장 · 동영상 \(videoCount)개"
            } else {
                messageLabel.text = "첨부 \(message.attachments.count)개"
            }
        } else {
            messageLabel.text = ""
        }
        
        // Sent time label
        timeLabel.text = formattedTime(message.sentAt)

        // 답장 미리보기 표시/토글
        if let rp = message.replyPreview {
            replyPreviewNameLabel.text = rp.sender
            replyPreviewMsgLabel.text = rp.isDeleted ? "삭제된 메시지입니다." : rp.text
            replyPreviewContainer.isHidden = false
            messageTopToBubbleTop?.isActive = false
            messageTopToReplyBottom?.isActive = true
            // Reply preview가 있으면 중앙정렬을 끄고, 위에서부터 배치
            messageCenterYConstraint?.isActive = false
        } else {
            replyPreviewNameLabel.text = nil
            replyPreviewMsgLabel.text = nil
            replyPreviewContainer.isHidden = true
            messageTopToReplyBottom?.isActive = false
            messageTopToBubbleTop?.isActive = true
            // Reply preview가 없으면 Y축 중앙 정렬
            messageCenterYConstraint?.isActive = true
        }
        
        if isMine {
            profileImageView.isHidden = true
            nicknameLabel.isHidden = true
            bubbleView.backgroundColor = .systemBlue

            bubbleTopToNickname?.isActive = false
            bubbleTopToTop?.isActive = true

            leadingConstraint?.isActive = false
            trailingConstraint?.isActive = true

            // 내 메시지: 버블 왼쪽 바깥에 시간
            timeRightOfBubbleLeading?.isActive = false
            timeLeftOfBubbleTrailing?.isActive = true
            timeLabel.textAlignment = .right
            timeLabel.textColor = .white
        } else {
            profileImageView.isHidden = false
            nicknameLabel.isHidden = false
            bubbleView.backgroundColor = /*UIColor(white: 0.2, alpha: 1.0)*/.lightGray

            bubbleTopToTop?.isActive = false
            bubbleTopToNickname?.isActive = true

            trailingConstraint?.isActive = false
            leadingConstraint?.isActive = true

            // 상대 메시지: 버블 오른쪽 바깥에 시간
            timeLeftOfBubbleTrailing?.isActive = false
            timeRightOfBubbleLeading?.isActive = true
            timeLabel.textAlignment = .left
            timeLabel.textColor = .white
        }
    }
    
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale.current
        return f
    }()
    private func formattedTime(_ date: Date?) -> String {
        guard let d = date else { return "" }
        return MessagePreviewView.timeFormatter.string(from: d)
    }
}
