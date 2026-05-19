//
//  MediaSectionImagePreviewCollectionViewCell.swift
//  OutPick
//
//  Created by 김가윤 on 5/15/25.
//

import UIKit

class MediaSectionImagePreviewCell: UICollectionViewCell {
    static let reuseIdentifier = "MediaSectionImagePreviewCell"
    typealias ThumbnailLoader = (ChatRoomSettingMediaItem) async -> UIImage?
    
    private lazy var imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        return imageView
    }()

    private lazy var placeholderImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "photo"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .tertiaryLabel
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private lazy var playBadgeView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "play.fill"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .white
        imageView.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        imageView.layer.cornerRadius = 14
        imageView.clipsToBounds = true
        imageView.isHidden = true
        return imageView
    }()

    private var loadTask: Task<Void, Never>?
    private var representedItemID: String?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        contentView.layer.masksToBounds = true
        contentView.layer.cornerRadius = 7
        contentView.backgroundColor = .secondarySystemFill
        
        contentView.addSubview(imageView)
        contentView.addSubview(placeholderImageView)
        contentView.addSubview(playBadgeView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            placeholderImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            placeholderImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            placeholderImageView.widthAnchor.constraint(equalToConstant: 24),
            placeholderImageView.heightAnchor.constraint(equalToConstant: 24),

            playBadgeView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            playBadgeView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            playBadgeView.widthAnchor.constraint(equalToConstant: 28),
            playBadgeView.heightAnchor.constraint(equalToConstant: 28)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        loadTask = nil
        representedItemID = nil
        imageView.image = nil
        placeholderImageView.isHidden = false
        playBadgeView.isHidden = true
    }

    func configure(with item: ChatRoomSettingMediaItem, thumbnailLoader: @escaping ThumbnailLoader) {
        representedItemID = item.id
        imageView.image = nil
        placeholderImageView.isHidden = false
        playBadgeView.isHidden = !item.isVideo
        loadTask?.cancel()

        loadTask = Task { [weak self] in
            let image = await thumbnailLoader(item)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.representedItemID == item.id else { return }
                self.imageView.image = image
                self.placeholderImageView.isHidden = image != nil
            }
        }
    }
}
