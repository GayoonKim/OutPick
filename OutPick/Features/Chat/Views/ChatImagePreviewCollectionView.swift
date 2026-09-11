//
//  ChatImagePreviewCollectionView.swift
//  OutPick
//
//  Created by 김가윤 on 3/28/25.
//

import Foundation
import UIKit

struct ChatImagePreviewItem {
    let id: String
    let displayIndex: Int
    let attachment: Attachment
    let durationText: String?

    static func stableID(messageID: String, attachment: Attachment) -> String {
        "\(messageID)#\(attachment.type.rawValue)#\(attachment.index)"
    }

    var previewPaths: [String] {
        var seen = Set<String>()
        return [attachment.thumbResourcePath, attachment.originalResourcePath].compactMap { path in
            guard !path.isEmpty else { return nil }
            guard seen.insert(path).inserted else { return nil }
            return path
        }
    }

    var isVideo: Bool {
        attachment.type == .video
    }

    var isAnimatedGIF: Bool {
        attachment.isAnimatedGIF
    }
}

class ChatImagePreviewCollectionView: UIView {
    enum Section: Hashable {
        case main
    }

    typealias ThumbnailLoader = (ChatImagePreviewItem) async -> UIImage?
    
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, String>!
    private var imagesCount = 0
    private var contentHeight: CGFloat = 0
    private var rows: [Int] = []
    private var previewItems: [ChatImagePreviewItem] = []
    private var itemsByID: [String: ChatImagePreviewItem] = [:]
    private var renderedImagesByItemID: [String: UIImage] = [:]
    private var thumbnailLoader: ThumbnailLoader?
    
    // MARK: - Compact sizing
    private let singleItemHeight: CGFloat = 200   // 단일 이미지 높이 줄임
    private let itemSpacing: CGFloat = 4          // 아이템 간격 살짝 키움

    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setupCollectionView()
        configureDataSource()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
    }
    
    private func setupCollectionView() {
        let layout = configureLayout()
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.isScrollEnabled = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.register(ChatImagePreviewCell.self, forCellWithReuseIdentifier: ChatImagePreviewCell.reuseIdentifier)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(collectionView)
        
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }
    
    private func configureLayout() -> UICollectionViewCompositionalLayout {
        return UICollectionViewCompositionalLayout { [weak self] (sectionIndex, environment) -> NSCollectionLayoutSection? in
            guard let self = self else { return nil }

            // Async thumbnail loading 중에는 잠시 0개 상태가 올 수 있다.
            // Compositional group은 최소 1개의 subitem이 필요하므로 fallback 레이아웃을 반환한다.
            if self.imagesCount == 0 {
                let itemSize = NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1.0),
                    heightDimension: .fractionalHeight(1.0)
                )
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                item.contentInsets = NSDirectionalEdgeInsets(
                    top: self.itemSpacing,
                    leading: self.itemSpacing,
                    bottom: self.itemSpacing,
                    trailing: self.itemSpacing
                )

                let fallbackHeight = max(1, self.contentHeight > 0 ? self.contentHeight : self.singleItemHeight)
                let groupSize = NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1.0),
                    heightDimension: .absolute(fallbackHeight)
                )
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
                return NSCollectionLayoutSection(group: group)
            }
            
            if self.imagesCount == 1 {
                // 단일 이미지일 때는 큰 크기로
                let itemSize = NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1.0),
                    heightDimension: .fractionalWidth(1.0)  // 정사각형 유지
                )
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                item.contentInsets = NSDirectionalEdgeInsets(top: self.itemSpacing,
                                                             leading: self.itemSpacing,
                                                             bottom: self.itemSpacing,
                                                             trailing: self.itemSpacing)
                
                let groupSize = NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1.0),
                    heightDimension: .absolute(self.singleItemHeight)
                )
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
                
                let section = NSCollectionLayoutSection(group: group)
                return section
            } else {
                
                // 동적 레이아웃
                var groups: [NSCollectionLayoutGroup] = []
                
                for itemsInRow in rows {
                    let itemWidth = 1.0 / CGFloat(itemsInRow)
                    
                    let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(itemWidth), heightDimension: .fractionalWidth(itemWidth))
                    let item = NSCollectionLayoutItem(layoutSize: itemSize)
                    item.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2)
                    
                    let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalWidth(itemWidth))
                    let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: Array(repeating: item, count: itemsInRow))
                    groups.append(group)
                }

                if groups.isEmpty {
                    let itemSize = NSCollectionLayoutSize(
                        widthDimension: .fractionalWidth(1.0),
                        heightDimension: .fractionalHeight(1.0)
                    )
                    let item = NSCollectionLayoutItem(layoutSize: itemSize)
                    let groupSize = NSCollectionLayoutSize(
                        widthDimension: .fractionalWidth(1.0),
                        heightDimension: .absolute(max(1, self.contentHeight))
                    )
                    let fallbackGroup = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
                    return NSCollectionLayoutSection(group: fallbackGroup)
                }
                
                let containerGroup = NSCollectionLayoutGroup.vertical(
                    layoutSize: NSCollectionLayoutSize(
                        widthDimension: .fractionalWidth(1.0),
                        heightDimension: .estimated(contentHeight)
                    ),
                    subitems: groups
                )
                
                let section = NSCollectionLayoutSection(group: containerGroup)
                return section
            }
        }
    }
    
    private func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { [weak self] collectionView, indexPath, itemID in
            guard let self, let item = self.itemsByID[itemID] else { return nil }

            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ChatImagePreviewCell.reuseIdentifier, for: indexPath) as! ChatImagePreviewCell
            self.configure(cell, with: item)

            return cell
        }

        var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
        snapshot.appendSections([Section.main])
        dataSource.apply(snapshot, animatingDifferences: false)
    }
    
    func updateCollectionView(
        _ items: [ChatImagePreviewItem],
        _ height: CGFloat,
        _ rows: [Int],
        thumbnailLoader: ThumbnailLoader?
    ) {
        let itemIDs = items.map(\.id)
        let validItemIDs = Set(itemIDs)
        let structureChanged = previewItems.map(\.id) != itemIDs
        let layoutChanged = imagesCount != items.count || contentHeight != height || self.rows != rows
        // 삭제/초기화된 항목의 요청은 실제 셀 재사용 시점까지 남겨두지 않는다.
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard let itemID = dataSource.itemIdentifier(for: indexPath), !validItemIDs.contains(itemID),
                  let cell = collectionView.cellForItem(at: indexPath) as? ChatImagePreviewCell else { continue }
            cell.resetContent()
        }
        self.imagesCount = items.count
        self.contentHeight = height
        self.rows = rows
        self.previewItems = items
        self.itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        self.thumbnailLoader = thumbnailLoader

        renderedImagesByItemID = renderedImagesByItemID.filter { validItemIDs.contains($0.key) }
        
        if layoutChanged {
            collectionView.setCollectionViewLayout(configureLayout(), animated: false)
        }
        if structureChanged {
            var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
            snapshot.appendSections([.main])
            snapshot.appendItems(itemIDs, toSection: .main)
            dataSource.apply(snapshot, animatingDifferences: false)
        }

        // 경로와 배지는 최신화하되 동일 첨부의 이미지와 로딩은 셀에서 유지한다.
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard let itemID = dataSource.itemIdentifier(for: indexPath),
                  let item = itemsByID[itemID],
                  let cell = collectionView.cellForItem(at: indexPath) as? ChatImagePreviewCell else { continue }
            configure(cell, with: item)
        }
        if layoutChanged || structureChanged { layoutIfNeeded() }
    }

    private func configure(_ cell: ChatImagePreviewCell, with item: ChatImagePreviewItem) {
        cell.configure(with: item, image: renderedImagesByItemID[item.id], thumbnailLoader: thumbnailLoader) { [weak self] image in
            guard let self, self.itemsByID[item.id] != nil, let image else { return }
            self.renderedImagesByItemID[item.id] = image
        }
    }

    func currentImages() -> [UIImage?] {
        previewItems.map { renderedImagesByItemID[$0.id] }
    }
    
    func index(at point: CGPoint) -> Int? {
        let p = self.convert(point, to: collectionView)
        return collectionView.indexPathForItem(at: p)?.item
    }
}
