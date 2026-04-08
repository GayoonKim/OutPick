//
//  ChatRoomMediaCollectionViewCell.swift
//  OutPick
//
//  Created by 김가윤 on 5/14/25.
//

import UIKit

class ChatRoomMediaCollectionViewCell: UICollectionViewCell {
    
    static let reuseIdentifier = "ChatRoomMediaCell"
    private var mediaItems: [ChatRoomSettingMediaItem] = []
    private var didAddHorizontalCollectionView = false
    private var thumbnailLoader: MediaSectionImagePreviewCell.ThumbnailLoader?
    
    /// 탭/더보기/섬네일 선택 시 갤러리 오픈을 요청하는 콜백 (startIndex: 진입 위치)
    var onOpenGallery: (() -> Void)?
    
    private lazy var imageVideoButtonImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "photo.on.rectangle.angled")
        imageView.tintColor = .systemGreen
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        return imageView
    }()
    
    private lazy var imageVideoLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16)
        label.textColor = .black
        label.translatesAutoresizingMaskIntoConstraints = false
        
        return label
    }()
    
    private lazy var horizontalCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 80, height: 80)
        layout.minimumLineSpacing = 5
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.isUserInteractionEnabled = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(MediaSectionImagePreviewCell.self, forCellWithReuseIdentifier: MediaSectionImagePreviewCell.reuseIdentifier)
        collectionView.register(MediaSectionMoreButtonCell.self, forCellWithReuseIdentifier: MediaSectionMoreButtonCell.reuseIdentifier)

        return collectionView
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        contentView.layer.cornerRadius = 10
        contentView.layer.masksToBounds = true
        contentView.backgroundColor = .white
        
        self.contentView.addSubview(imageVideoButtonImageView)
        self.contentView.addSubview(imageVideoLabel)

        NSLayoutConstraint.activate([
            imageVideoButtonImageView.heightAnchor.constraint(equalToConstant: 25),
            imageVideoButtonImageView.widthAnchor.constraint(equalToConstant: 25),
            imageVideoButtonImageView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 10),
            imageVideoButtonImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            
            imageVideoLabel.centerYAnchor.constraint(equalTo: imageVideoButtonImageView.centerYAnchor),
            imageVideoLabel.leadingAnchor.constraint(equalTo: imageVideoButtonImageView.trailingAnchor, constant: 10),
        ])
    }
    
    func configureCell(
        for mediaItems: [ChatRoomSettingMediaItem],
        thumbnailLoader: @escaping MediaSectionImagePreviewCell.ThumbnailLoader
    ) {
        imageVideoLabel.text = "사진/동영상"
        self.mediaItems = Self.uniqueMediaItems(from: mediaItems)
        self.thumbnailLoader = thumbnailLoader
        horizontalCollectionView.isHidden = self.mediaItems.isEmpty
        
        // 내부 미리보기 갱신
        if didAddHorizontalCollectionView {
            horizontalCollectionView.reloadData()
        }
        
        if !self.mediaItems.isEmpty {
            if !didAddHorizontalCollectionView {
                self.contentView.addSubview(horizontalCollectionView)
                
                NSLayoutConstraint.activate([
                    horizontalCollectionView.topAnchor.constraint(equalTo: imageVideoButtonImageView.bottomAnchor, constant: 10),
                    horizontalCollectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
                    horizontalCollectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
                    horizontalCollectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
                ])
                
                didAddHorizontalCollectionView = true
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onOpenGallery = nil
        thumbnailLoader = nil
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func uniqueMediaItems(from items: [ChatRoomSettingMediaItem]) -> [ChatRoomSettingMediaItem] {
        var knownIDs = Set<String>()
        var knownContentKeys = Set<String>()

        return items.filter { item in
            guard knownIDs.insert(item.id).inserted else { return false }

            let dedupeKeys = item.dedupeKeys
            if !dedupeKeys.isEmpty {
                guard knownContentKeys.isDisjoint(with: dedupeKeys) else { return false }
                knownContentKeys.formUnion(dedupeKeys)
            }

            return true
        }
    }
}

extension ChatRoomMediaCollectionViewCell: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard !self.mediaItems.isEmpty else { return 0 }
        return self.mediaItems.count + 1
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if indexPath.item < mediaItems.count {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MediaSectionImagePreviewCell.reuseIdentifier, for: indexPath) as! MediaSectionImagePreviewCell
            if let thumbnailLoader {
                cell.configure(with: self.mediaItems[indexPath.item], thumbnailLoader: thumbnailLoader)
            }
            
            return cell
        } else {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MediaSectionMoreButtonCell.reuseIdentifier, for: indexPath) as! MediaSectionMoreButtonCell
            return cell
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onOpenGallery?()
    }
}
