//
//  ChatLatestMessageJumpView.swift
//  OutPick
//
//  Created by Codex on 7/17/26.
//

import UIKit

final class ChatLatestMessageJumpView: UIControl {
    private var representedTargetSeq: Int64?

    private let previewImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.tintColor = OutPickTheme.ColorToken.textSecondary
        imageView.backgroundColor = OutPickTheme.ColorToken.surfacePressed
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 10
        imageView.layer.masksToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = OutPickTheme.ColorToken.textSecondary
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()

    private let previewLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = OutPickTheme.ColorToken.textPrimary
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()

    private lazy var textStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [titleLabel, previewLabel])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 2
        return stack
    }()

    private let arrowView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "arrow.down"))
        imageView.tintColor = OutPickTheme.ColorToken.textPrimary
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.color = OutPickTheme.ColorToken.accent
        indicator.hidesWhenStopped = true
        return indicator
    }()

    private lazy var contentStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [previewImageView, textStack, arrowView, loadingIndicator])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted
                ? OutPickTheme.ColorToken.surfacePressed
                : OutPickTheme.ColorToken.surfaceElevated
        }
    }

    func configure(_ presentation: ChatLatestJumpPresentation) {
        isHidden = !presentation.isVisible
        isEnabled = presentation.isVisible && !presentation.isLoading
        alpha = isEnabled ? 1 : 0.82

        representedTargetSeq = presentation.preview?.targetSeq
        let senderName = presentation.preview?.senderName
        titleLabel.text = (senderName?.isEmpty == false) ? senderName : "새 메시지"
        previewLabel.text = presentation.preview?.text ?? "새 메시지가 도착했어요"
        previewImageView.image = defaultImage(for: presentation.preview?.kind ?? .generic)
        previewImageView.contentMode = .center

        if presentation.isLoading {
            loadingIndicator.startAnimating()
            arrowView.isHidden = true
        } else {
            loadingIndicator.stopAnimating()
            arrowView.isHidden = false
        }

        accessibilityLabel = [titleLabel.text, previewLabel.text]
            .compactMap { $0 }
            .joined(separator: ", ")
        accessibilityValue = presentation.unreadAccessibilityText
        accessibilityHint = presentation.isLoading
            ? "최신 메시지를 불러오는 중입니다."
            : "두 번 탭하여 이 메시지로 이동합니다."
    }

    func setCachedPreviewImage(_ image: UIImage, targetSeq: Int64) {
        guard representedTargetSeq == targetSeq else { return }
        previewImageView.image = image
        previewImageView.contentMode = .scaleAspectFill
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = OutPickTheme.ColorToken.surfaceElevated
        layer.cornerRadius = 16
        layer.borderWidth = 1
        layer.borderColor = OutPickTheme.ColorToken.borderStrong.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.22
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 3)

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityIdentifier = "chat.latestMessageJump"

        addSubview(contentStack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 60),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 250),
            previewImageView.widthAnchor.constraint(equalToConstant: 40),
            previewImageView.heightAnchor.constraint(equalToConstant: 40),
            arrowView.widthAnchor.constraint(equalToConstant: 16),
            arrowView.heightAnchor.constraint(equalToConstant: 16),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            contentStack.topAnchor.constraint(equalTo: topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func defaultImage(for kind: ChatLatestMessagePreviewKind) -> UIImage? {
        let systemName: String
        switch kind {
        case .text:
            systemName = "message.fill"
        case .image:
            systemName = "photo.fill"
        case .video:
            systemName = "play.rectangle.fill"
        case .lookbook:
            systemName = "book.closed.fill"
        case .generic:
            systemName = "arrow.down.circle.fill"
        }
        return UIImage(systemName: systemName)
    }
}
