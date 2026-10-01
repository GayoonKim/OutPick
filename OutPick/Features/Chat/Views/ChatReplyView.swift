//
//  ChatReplyView.swift
//  OutPick
//
//  Created by 김가윤 on 9/9/25.
//

import Foundation
import UIKit

class ChatReplyView: UIView {
    var onCancel: (() -> Void)?
    private var representedMessage: ChatMessage?
    private var expiryTimer: Timer?
    private var senderLeading: NSLayoutConstraint!
    private var messageLeading: NSLayoutConstraint!
    private let thumbnailView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.clipsToBounds = true
        view.layer.cornerRadius = 4
        view.tintColor = OutPickTheme.ColorToken.iconSecondary
        view.accessibilityIdentifier = "chat.reply.thumbnail"
        return view
    }()
    private lazy var senderLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        
        return label
    }()
    
    private lazy var messageLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11, weight: .regular)
        label.translatesAutoresizingMaskIntoConstraints = false
        
        return label
    }()
    
    private lazy var cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "xmark")
        config.buttonSize = .small
        config.imagePlacement = .trailing
        config.baseForegroundColor = OutPickTheme.ColorToken.iconSecondary
        button.configuration = config
        
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        self.layer.cornerRadius = self.frame.height / 2
    }
    
    private func setupViews() {
        self.backgroundColor = OutPickTheme.ColorToken.backgroundRaised
        self.layer.borderColor = OutPickTheme.ColorToken.borderSubtle.cgColor
        self.layer.borderWidth = 1
        
        addSubview(senderLabel)
        addSubview(messageLabel)
        addSubview(cancelButton)
        addSubview(thumbnailView)
        senderLeading = senderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20)
        messageLeading = messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20)
        NSLayoutConstraint.activate([
            senderLeading,
            senderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            senderLabel.trailingAnchor.constraint(lessThanOrEqualTo: cancelButton.leadingAnchor, constant: -8),
            
            messageLeading,
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -50),
            messageLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            messageLabel.topAnchor.constraint(equalTo: senderLabel.bottomAnchor, constant: 3),
            
            cancelButton.widthAnchor.constraint(equalToConstant: 16),
            cancelButton.heightAnchor.constraint(equalToConstant: 16),
            cancelButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            cancelButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            thumbnailView.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 28),
            thumbnailView.heightAnchor.constraint(equalToConstant: 28)
        ])
        
        cancelButton.addTarget(self, action: #selector(handleCancel), for: .touchUpInside)
    }
    
    @objc private func handleCancel() {
        self.isHidden = true
        expiryTimer?.invalidate()
        onCancel?()
    }
    
    func configure(with message: ChatMessage, now: Date = Date()) {
        representedMessage = message
        expiryTimer?.invalidate()
        senderLabel.textColor = OutPickTheme.ColorToken.textPrimary
        messageLabel.textColor = OutPickTheme.ColorToken.textSecondary
        senderLabel.text = message.senderNickname
        messageLabel.text = Self.previewText(for: message, now: now)
        let attachments = message.displayableAttachments
        thumbnailView.isHidden = attachments.isEmpty
        thumbnailView.contentMode = .scaleAspectFit
        thumbnailView.image = attachments.isEmpty ? nil : UIImage(systemName: attachments.first?.type == .video ? "video" : "photo")
        senderLeading.constant = attachments.isEmpty ? 20 : 52
        messageLeading.constant = senderLeading.constant
        accessibilityLabel = "\(message.senderNickname), \(messageLabel.text ?? "")"
        if message.mediaExpiresAt.map({ $0 > now }) ?? false { scheduleExpiry() }
    }

    static func previewText(for message: ChatMessage, now: Date = Date()) -> String {
        if message.isDeleted { return "삭제된 메시지입니다" }
        let attachments = message.displayableAttachments
        guard !attachments.isEmpty else {
            return message.isLookbookShareMessage ? message.lookbookSharePreviewText : message.msg ?? ""
        }
        let photos = attachments.filter { $0.type == .image }.count
        let videos = attachments.filter { $0.type == .video }.count
        let kind = videos > 0 ? "동영상" : "사진 \(photos)장"
        return message.mediaExpiresAt.map { $0 > now } ?? false
            ? kind : "\(kind) · 보관 기간 만료"
    }

    func setThumbnail(_ image: UIImage, messageID: String, now: Date = Date()) {
        guard let message = representedMessage, message.ID == messageID, !isHidden else { return }
        guard !message.isDeleted, message.mediaExpiresAt.map({ $0 > now }) ?? false else {
            configure(with: message, now: now)
            return
        }
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.image = image
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        expiryTimer?.invalidate()
        guard window != nil, let message = representedMessage else { return }
        if !message.displayableAttachments.isEmpty,
           message.mediaExpiresAt.map({ $0 <= Date() }) ?? true {
            configure(with: message)
        } else {
            scheduleExpiry()
        }
    }

    private func scheduleExpiry() {
        guard window != nil, let message = representedMessage,
              !message.displayableAttachments.isEmpty,
              let expiry = message.mediaExpiresAt, expiry > Date() else { return }
        let timer = Timer(timeInterval: max(0.01, expiry.timeIntervalSinceNow), repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let current = self.representedMessage else { return }
                self.configure(with: current)
            }
        }
        expiryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    deinit { expiryTimer?.invalidate() }
}
