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
        imageView.tintColor = .tertiaryLabel
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        indicator.color = .secondaryLabel
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

    private var representedItemID: String?
    private var loadTask: Task<Void, Never>?

    override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        loadTask = nil
        representedItemID = nil
        imageView.image = nil
        placeholderImageView.isHidden = false
        loadingIndicator.stopAnimating()
        videoBadgeView.isHidden = true
        videoDurationLabel.isHidden = true
        videoDurationLabel.text = nil
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 10
        contentView.layer.masksToBounds = true
        contentView.backgroundColor = .secondarySystemFill

        contentView.addSubview(imageView)
        contentView.addSubview(placeholderImageView)
        contentView.addSubview(loadingIndicator)
        contentView.addSubview(videoBadgeView)
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
            videoDurationLabel.centerYAnchor.constraint(equalTo: videoBadgeView.centerYAnchor)
        ])
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.isOpaque = true
        imageView.backgroundColor = .secondarySystemBackground
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
        representedItemID = item.id
        loadTask?.cancel()
        imageView.image = image
        placeholderImageView.isHidden = image != nil
        loadingIndicator.stopAnimating()

        if item.isVideo {
            videoBadgeView.isHidden = false
            videoDurationLabel.text = item.durationText
            videoDurationLabel.isHidden = item.durationText == nil
        } else {
            videoBadgeView.isHidden = true
            videoDurationLabel.text = nil
            videoDurationLabel.isHidden = true
        }

        guard image == nil, let thumbnailLoader else { return }
        loadingIndicator.startAnimating()

        loadTask = Task { [weak self] in
            let loadedImage = await thumbnailLoader(item)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.representedItemID == item.id else { return }
                self.imageView.image = loadedImage
                self.placeholderImageView.isHidden = loadedImage != nil
                self.loadingIndicator.stopAnimating()
                onImageLoaded?(loadedImage)
            }
        }
    }
    
    
}
