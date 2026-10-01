//
//  ChatImagePreviewCell.swift
//  OutPick
//
//  Created by 김가윤 on 3/14/25.
//

import UIKit

class ChatImagePreviewCell: UICollectionViewCell {
    static let reuseIdentifier = "ChatImagePreviewCell"
    
    private let imageView = UIImageView()
    private let placeholderImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "photo"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = OutPickTheme.ColorToken.iconSecondary
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        indicator.color = OutPickTheme.ColorToken.accent
        return indicator
    }()

    private let videoBadgeView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        view.layer.cornerRadius = 11
        view.clipsToBounds = true
        view.isHidden = true
        return view
    }()

    private let videoIconView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "play.fill"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let videoDurationLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .white
        label.isHidden = true
        return label
    }()

    private let gifBadgeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "GIF"
        label.textColor = .white
        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.textAlignment = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        label.layer.cornerRadius = 6
        label.clipsToBounds = true
        label.isHidden = true
        label.isAccessibilityElement = true
        label.accessibilityLabel = "GIF 이미지"
        return label
    }()

    private let expiredLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .white
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.minimumScaleFactor = 0.8
        label.adjustsFontSizeToFitWidth = true
        label.backgroundColor = UIColor.black.withAlphaComponent(0.62)
        label.isHidden = true
        label.isAccessibilityElement = true
        return label
    }()

    private var representedItemID: String?
    private var representedPath = ""
    private var representedResource: ChatMediaCacheResource?
    private var representedIsVideo = false
    private var spinnerSpan: ImageCacheMetrics.Span?
    var diagnostics = ImageCacheMetrics.shared

    private func stopSpinner(reason: String) {
        diagnostics.end(spinnerSpan, outcome: reason)
        spinnerSpan = nil
        loadingIndicator.stopAnimating()
    }
    override func prepareForReuse() {
        super.prepareForReuse()
        resetContent()
    }

    func resetContent() {
        stopSpinner(reason: "reset")
        representedPath = ""
        representedResource = nil
        representedIsVideo = false
        representedItemID = nil
        accessibilityValue = nil
        imageView.image = nil
        placeholderImageView.isHidden = false
        loadingIndicator.stopAnimating()
        videoBadgeView.isHidden = true
        videoDurationLabel.isHidden = true
        videoDurationLabel.text = nil
        gifBadgeLabel.isHidden = true
        expiredLabel.isHidden = true
        expiredLabel.text = nil
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "chat.media.preview"
        contentView.layer.cornerRadius = 10
        contentView.layer.masksToBounds = true
        contentView.backgroundColor = OutPickTheme.ColorToken.surfaceBase

        contentView.addSubview(imageView)
        contentView.addSubview(placeholderImageView)
        contentView.addSubview(loadingIndicator)
        contentView.addSubview(videoBadgeView)
        contentView.addSubview(gifBadgeLabel)
        contentView.addSubview(expiredLabel)
        videoBadgeView.addSubview(videoIconView)
        videoBadgeView.addSubview(videoDurationLabel)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            placeholderImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            placeholderImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            placeholderImageView.widthAnchor.constraint(equalToConstant: 24),
            placeholderImageView.heightAnchor.constraint(equalToConstant: 24),

            loadingIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            videoBadgeView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            videoBadgeView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            videoBadgeView.heightAnchor.constraint(equalToConstant: 22),

            videoIconView.leadingAnchor.constraint(equalTo: videoBadgeView.leadingAnchor, constant: 7),
            videoIconView.centerYAnchor.constraint(equalTo: videoBadgeView.centerYAnchor),
            videoIconView.widthAnchor.constraint(equalToConstant: 10),
            videoIconView.heightAnchor.constraint(equalToConstant: 10),

            videoDurationLabel.leadingAnchor.constraint(equalTo: videoIconView.trailingAnchor, constant: 5),
            videoDurationLabel.trailingAnchor.constraint(equalTo: videoBadgeView.trailingAnchor, constant: -7),
            videoDurationLabel.centerYAnchor.constraint(equalTo: videoBadgeView.centerYAnchor),

            gifBadgeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            gifBadgeLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            gifBadgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 32),
            gifBadgeLabel.heightAnchor.constraint(equalToConstant: 22)
        ])
        NSLayoutConstraint.activate([
            expiredLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            expiredLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            expiredLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 4),
            expiredLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -4)
        ])
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.isOpaque = true
        imageView.backgroundColor = OutPickTheme.ColorToken.surfaceBase
        imageView.accessibilityIgnoresInvertColors = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    func configure(
        with item: ChatImagePreviewItem,
        image: UIImage?
    ) {
        if representedItemID != item.id {
            resetContent()
            representedItemID = item.id
        }
        representedPath = item.attachment.thumbResourcePath
        representedResource = item.cacheResource
        representedIsVideo = item.isVideo
        if item.cacheResource.isExpired {
            showExpired(isVideo: item.isVideo)
            return
        }
        expiredLabel.isHidden = true
        if let image { imageView.image = image }
        if imageView.image != nil {
            diagnostics.mark("chatPreview.imageAssigned", key: representedPath, parent: spinnerSpan?.id, outcome: "configure")
        }
        placeholderImageView.isHidden = imageView.image != nil
        videoBadgeView.isHidden = !item.isVideo
        videoDurationLabel.text = item.isVideo ? item.durationText : nil
        videoDurationLabel.isHidden = !item.isVideo || item.durationText == nil
        gifBadgeLabel.isHidden = !item.isAnimatedGIF
        stopSpinner(reason: imageView.image == nil ? "configureEmpty" : "configureImage")
    }

    func render(_ state: ChatMediaViewportController.Presentation, memoryCacheHit: Bool? = nil) {
        if representedResource?.isExpired == true {
            showExpired(isVideo: representedIsVideo)
            return
        }
        switch state {
        case .image(let image):
            if imageView.image !== image { imageView.image = image }
            diagnostics.mark("chatPreview.imageAssigned", key: representedPath, parent: spinnerSpan?.id, outcome: "render")
            stopSpinner(reason: "image")
        case .loading:
            if imageView.image == nil {
                if !loadingIndicator.isAnimating {
                    spinnerSpan = diagnostics.begin("chatPreview.spinner", key: representedPath)
                    let cache = memoryCacheHit.map { $0 ? "memoryHit" : "memoryMiss" } ?? "memoryUnknown"
                    diagnostics.mark("chatPreview.spinnerState", key: representedPath, parent: spinnerSpan?.id,
                                     outcome: "\(cache)_\(window == nil ? "offWindow" : "inWindow")")
                }
                loadingIndicator.startAnimating()
            }
        case .idle:
            // 수요 이탈은 작업 취소다. 이미 표시한 픽셀은 재사용/경로 변경 때 정리한다.
            ImageCacheMetrics.shared.mark("chatPreview.cellIdle", outcome: imageView.image == nil ? "empty" : "retained")
            stopSpinner(reason: "idle")
        case .failed:
            stopSpinner(reason: "failed")
        }
        placeholderImageView.isHidden = imageView.image != nil
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ChatMediaViewportQA") {
            accessibilityValue = imageView.image == nil ? "placeholder" : "loaded"
        }
        #endif
    }

    private func showExpired(isVideo: Bool) {
        stopSpinner(reason: "expired")
        imageView.image = nil
        placeholderImageView.isHidden = false
        loadingIndicator.stopAnimating()
        videoBadgeView.isHidden = true
        videoDurationLabel.isHidden = true
        gifBadgeLabel.isHidden = true
        expiredLabel.text = isVideo ? "보관 기간이 만료된 동영상입니다" : "보관 기간이 만료된 사진입니다"
        expiredLabel.isHidden = true
        accessibilityValue = expiredLabel.text
    }

    deinit { diagnostics.end(spinnerSpan, outcome: "deinit") }
}
