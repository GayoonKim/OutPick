//
//  LookbookShareMessageContentView.swift
//  OutPick
//
//  Created by Codex on 6/17/26.
//

import UIKit

final class LookbookShareMessageContentView: UIControl {
    private let thumbnailView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.layer.cornerRadius = 8
        view.backgroundColor = OutPickTheme.ColorToken.surfaceElevated
        view.tintColor = OutPickTheme.ColorToken.textTertiary
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = OutPickTheme.ColorToken.textPrimary
        label.numberOfLines = 2
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12)
        label.textColor = OutPickTheme.ColorToken.textSecondary
        label.numberOfLines = 1
        return label
    }()

    private let chevronView: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "chevron.right"))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        view.tintColor = OutPickTheme.ColorToken.accent
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
        return view
    }()

    private let unavailableLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13)
        label.textColor = OutPickTheme.ColorToken.textSecondary
        label.numberOfLines = 2
        label.text = "공유 정보를 불러올 수 없습니다."
        return label
    }()

    private var representedThumbnailPath: String?
    private var representedContentType: LookbookSharedContent.ContentType?
    private var textThumbnailLeading: NSLayoutConstraint?
    private var textNameLeading: NSLayoutConstraint?
    private var minimumHeight: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func prepareForReuse() {
        representedThumbnailPath = nil
        representedContentType = nil
        textNameLeading?.isActive = false
        textThumbnailLeading?.isActive = true
        minimumHeight?.constant = 76
        // SF Symbol의 alignment inset이 썸네일 frame을 바꾸지 않게 한다.
        thumbnailView.image = UIImage(systemName: "photo")?.withAlignmentRectInsets(.zero)
        thumbnailView.contentMode = .center
        thumbnailView.isHidden = false
        chevronView.isHidden = false
        titleLabel.text = nil
        subtitleLabel.text = nil
        unavailableLabel.isHidden = true
        isEnabled = true
    }

    func configure(
        with content: LookbookSharedContent?
    ) {
        if representedThumbnailPath != content?.displayThumbnailPath || representedContentType != content?.contentType {
            prepareForReuse()
        }

        guard let content else {
            configureUnavailable()
            return
        }

        titleLabel.text = content.compactDisplayTitle
        subtitleLabel.text = content.compactDisplaySubtitle ?? content.fallbackPreviewText
        representedContentType = content.contentType
        let isBrand = content.contentType == .brand
        thumbnailView.isHidden = isBrand
        textThumbnailLeading?.isActive = !isBrand
        textNameLeading?.isActive = isBrand
        minimumHeight?.constant = isBrand ? 56 : 76

        guard let path = content.displayThumbnailPath, !path.isEmpty else { return }
        representedThumbnailPath = path
    }

    func thumbnailFrame(in view: UIView) -> CGRect {
        thumbnailView.convert(thumbnailView.bounds, to: view)
    }

    func render(path: String, state: ChatMediaViewportController.Presentation) {
        guard representedThumbnailPath == path else { return }
        if case .image(let image) = state {
            if thumbnailView.image !== image { thumbnailView.image = image }
            thumbnailView.contentMode = .scaleAspectFill
        }
    }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = OutPickTheme.ColorToken.surfaceBase
        layer.cornerRadius = 12
        layer.borderColor = OutPickTheme.ColorToken.borderSubtle.cgColor
        layer.borderWidth = 1
        clipsToBounds = true

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 3
        textStack.alignment = .fill

        addSubview(thumbnailView)
        addSubview(textStack)
        addSubview(chevronView)
        addSubview(unavailableLabel)
        textThumbnailLeading = textStack.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 10)
        textNameLeading = textStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12)
        minimumHeight = heightAnchor.constraint(greaterThanOrEqualToConstant: 76)

        NSLayoutConstraint.activate([
            thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            thumbnailView.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 56),
            thumbnailView.heightAnchor.constraint(equalToConstant: 56),

            textThumbnailLeading!,
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: chevronView.leadingAnchor, constant: -8),

            chevronView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            chevronView.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: 14),
            chevronView.heightAnchor.constraint(equalToConstant: 18),

            unavailableLabel.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 10),
            unavailableLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            unavailableLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevronView.leadingAnchor, constant: -8),

            minimumHeight!
        ])
    }

    private func configureUnavailable() {
        titleLabel.text = nil
        subtitleLabel.text = nil
        unavailableLabel.isHidden = false
        thumbnailView.image = UIImage(systemName: "exclamationmark.triangle")?.withAlignmentRectInsets(.zero)
        thumbnailView.contentMode = .center
        chevronView.isHidden = true
        isEnabled = false
    }
}
