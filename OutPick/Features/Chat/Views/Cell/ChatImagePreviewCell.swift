//
//  ChatImagePreviewCell.swift
//  OutPick
//
//  Created by 김가윤 on 3/14/25.
//

import UIKit

class ChatImagePreviewCell: UICollectionViewCell {
    static let reuseIdentifier = "ChatImagePreviewCell"
    typealias ThumbnailLoader = (ChatImagePreviewItem) async -> UIImage?
    
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

    private var representedItemID: String?
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = UUID()
    private var latestItem: ChatImagePreviewItem?
    private var thumbnailLoader: ThumbnailLoader?
    private var onImageLoaded: ((UIImage?) -> Void)?

    override func prepareForReuse() {
        super.prepareForReuse()
        resetContent()
    }

    func resetContent() {
        loadTask?.cancel()
        loadTask = nil
        loadGeneration = UUID()
        latestItem = nil
        thumbnailLoader = nil
        onImageLoaded = nil
        representedItemID = nil
        imageView.image = nil
        placeholderImageView.isHidden = false
        loadingIndicator.stopAnimating()
        videoBadgeView.isHidden = true
        videoDurationLabel.isHidden = true
        videoDurationLabel.text = nil
        gifBadgeLabel.isHidden = true
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 10
        contentView.layer.masksToBounds = true
        contentView.backgroundColor = OutPickTheme.ColorToken.surfaceBase

        contentView.addSubview(imageView)
        contentView.addSubview(placeholderImageView)
        contentView.addSubview(loadingIndicator)
        contentView.addSubview(videoBadgeView)
        contentView.addSubview(gifBadgeLabel)
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
        image: UIImage?,
        thumbnailLoader: ThumbnailLoader?,
        onImageLoaded: ((UIImage?) -> Void)? = nil
    ) {
        if representedItemID != item.id {
            resetContent()
            representedItemID = item.id
        }
        latestItem = item
        self.thumbnailLoader = thumbnailLoader
        self.onImageLoaded = onImageLoaded
        if let image {
            imageView.image = image
            loadTask?.cancel()
            loadTask = nil
            loadGeneration = UUID()
        }
        placeholderImageView.isHidden = imageView.image != nil

        if item.isVideo {
            videoBadgeView.isHidden = false
            videoDurationLabel.text = item.durationText
            videoDurationLabel.isHidden = item.durationText == nil
        } else {
            videoBadgeView.isHidden = true
            videoDurationLabel.text = nil
            videoDurationLabel.isHidden = true
        }
        gifBadgeLabel.isHidden = !item.isAnimatedGIF

        if imageView.image != nil {
            loadingIndicator.stopAnimating()
            return
        }
        guard loadTask == nil else { return }
        startLoadingLatestItem()
    }

    private func startLoadingLatestItem() {
        guard let item = latestItem, let thumbnailLoader else {
            loadingIndicator.stopAnimating()
            return
        }
        let generation = UUID()
        loadGeneration = generation
        loadingIndicator.startAnimating()

        loadTask = Task { @MainActor [weak self] in
            let loadedImage = await thumbnailLoader(item)
            guard !Task.isCancelled, let self,
                  self.loadGeneration == generation,
                  self.representedItemID == item.id else { return }
            self.loadTask = nil
            // 로컬 로딩 중 서버 확정이 도착했으면 실패한 경우에만 최신 경로로 복구한다.
            if loadedImage == nil, self.latestItem?.previewPaths != item.previewPaths {
                self.startLoadingLatestItem()
                return
            }
            self.imageView.image = loadedImage
            self.placeholderImageView.isHidden = loadedImage != nil
            self.loadingIndicator.stopAnimating()
            self.onImageLoaded?(loadedImage)
        }
    }
    
    
}
