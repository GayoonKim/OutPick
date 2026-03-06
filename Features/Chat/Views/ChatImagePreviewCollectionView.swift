//
//  ChatImagePreviewCollectionView.swift
//  OutPick
//
//  Created by 김가윤 on 3/28/25.
//

import Foundation
import UIKit

struct ChatImagePreviewItem: Hashable {
    let id: String
    let displayIndex: Int
    let attachment: Attachment
    let durationText: String?

    var previewPaths: [String] {
        var seen = Set<String>()
        return [attachment.pathThumb, attachment.pathOriginal].compactMap { path in
            guard !path.isEmpty else { return nil }
            guard seen.insert(path).inserted else { return nil }
            return path
        }
    }

    var isVideo: Bool {
        attachment.type == .video
    }
}

class ChatImagePreviewCollectionView: UIView {
    enum Section: Hashable {
        case main
    }

    typealias ThumbnailLoader = (ChatImagePreviewItem) async -> UIImage?
    
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, ChatImagePreviewItem>!
    private var imagesCount = 0
    private var contentHeight: CGFloat = 0
    private var rows: [Int] = []
    private var previewItems: [ChatImagePreviewItem] = []
    private var renderedImagesByDisplayIndex: [Int: UIImage] = [:]
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
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { [weak self] collectionView, indexPath, item in
            guard let self else { return nil }

            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ChatImagePreviewCell.reuseIdentifier, for: indexPath) as! ChatImagePreviewCell
            let renderedImage = self.renderedImagesByDisplayIndex[item.displayIndex]
            cell.configure(
                with: item,
                image: renderedImage,
                thumbnailLoader: self.thumbnailLoader
            ) { [weak self] image in
                guard let self, let image else { return }
                self.renderedImagesByDisplayIndex[item.displayIndex] = image
            }

            return cell
        }

        var snapshot = NSDiffableDataSourceSnapshot<Section, ChatImagePreviewItem>()
        snapshot.appendSections([Section.main])
        dataSource.apply(snapshot, animatingDifferences: false)
    }
    
    func updateCollectionView(
        _ items: [ChatImagePreviewItem],
        _ height: CGFloat,
        _ rows: [Int],
        thumbnailLoader: ThumbnailLoader?
    ) {
        self.imagesCount = items.count
        self.contentHeight = height
        self.rows = rows
        self.previewItems = items
        self.thumbnailLoader = thumbnailLoader

        let validDisplayIndices = Set(items.map(\.displayIndex))
        renderedImagesByDisplayIndex = renderedImagesByDisplayIndex.filter { validDisplayIndices.contains($0.key) }
        
        // 컬렉션 뷰 레이아웃 업데이트
        collectionView.setCollectionViewLayout(configureLayout(), animated: false)
        
        let itemBySection = [Section.main: items]
        dataSource.applySnapshotUsing(sectionIDs: [Section.main], itemsBySection: itemBySection, animatingDifferences: false)
        
        self.layoutIfNeeded()
    }

    func currentImages() -> [UIImage?] {
        previewItems.map { renderedImagesByDisplayIndex[$0.displayIndex] }
    }
    
    func index(at point: CGPoint) -> Int? {
        let p = self.convert(point, to: collectionView)
        return collectionView.indexPathForItem(at: p)?.item
    }
}
