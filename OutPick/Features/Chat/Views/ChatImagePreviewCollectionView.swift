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
        return [attachment.thumbResourcePath].compactMap { path in
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

    
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, String>!
    private var imagesCount = 0
    private var contentHeight: CGFloat = 0
    private var rows: [Int] = []
    private var previewItems: [ChatImagePreviewItem] = []
    private var itemsByID: [String: ChatImagePreviewItem] = [:]
    private var renderedImagesByItemID: [String: UIImage] = [:]
    private var cachedImage: (String) -> UIImage? = { _ in nil }
    
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
        UICollectionViewCompositionalLayout { [weak self] _, environment in
            guard let self else { return nil }
            let width = environment.container.effectiveContentSize.width
            let count = max(1, self.imagesCount)
            let height = max(1, ChatMediaPreviewLayout.height(count: count, width: width))
            let group = NSCollectionLayoutGroup.custom(
                layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(height))
            ) { _ in
                ChatMediaPreviewLayout.frames(count: count, width: width).map {
                    NSCollectionLayoutGroupCustomItem(frame: $0)
                }
            }
            return NSCollectionLayoutSection(group: group)
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
        cachedImage: @escaping (String) -> UIImage? = { _ in nil }
    ) {
        self.cachedImage = cachedImage
        let itemIDs = items.map(\.id)
        let validItemIDs = Set(itemIDs)
        let structureChanged = previewItems.map(\.id) != itemIDs
        let layoutChanged = imagesCount != items.count || contentHeight != height || self.rows != rows
        let changedIDs = Set(items.compactMap { item -> String? in
            guard let old = itemsByID[item.id], old.attachment.thumbResourcePath != item.attachment.thumbResourcePath else { return nil }
            let oldPath = old.attachment.thumbResourcePath
            return oldPath.hasPrefix("/") || oldPath.hasPrefix("file://") ? nil : item.id
        })
        for id in changedIDs { renderedImagesByItemID[id] = nil }
        // 삭제/초기화된 항목의 요청은 실제 셀 재사용 시점까지 남겨두지 않는다.
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard let itemID = dataSource.itemIdentifier(for: indexPath), !validItemIDs.contains(itemID) || changedIDs.contains(itemID),
                  let cell = collectionView.cellForItem(at: indexPath) as? ChatImagePreviewCell else { continue }
            cell.resetContent()
        }
        self.imagesCount = items.count
        self.contentHeight = height
        self.rows = rows
        self.previewItems = items
        self.itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

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
        if renderedImagesByItemID[item.id] == nil {
            let image = cachedImage(item.attachment.thumbResourcePath)
            renderedImagesByItemID[item.id] = image
            ImageCacheMetrics.shared.mark("chatPreview.cellCache", key: item.attachment.thumbResourcePath,
                                          outcome: image == nil ? "miss" : "hit")
        }
        cell.configure(with: item, image: renderedImagesByItemID[item.id])
    }

    func viewportItems(in view: UIView) -> [ChatMediaViewportItem] {
        previewItems.enumerated().compactMap { index, item in
            guard let attributes = collectionView.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: index, section: 0)) else { return nil }
            let frame = collectionView.convert(attributes.frame, to: view).intersection(convert(bounds, to: view))
            return ChatMediaViewportItem(id: item.id, path: item.attachment.thumbResourcePath, frame: frame)
        }
    }

    func render(id: String, path: String, state: ChatMediaViewportController.Presentation) {
        guard let item = itemsByID[id], item.attachment.thumbResourcePath == path else { return }
        var loadingCacheHit: Bool?
        if case .loading = state {
            if let image = renderedImagesByItemID[id] ?? cachedImage(path) {
                ImageCacheMetrics.shared.mark("chatPreview.loadingResolution", key: path, outcome: "imageAvailable")
                render(id: id, path: path, state: .image(image))
                return
            }
            loadingCacheHit = false
            ImageCacheMetrics.shared.mark("chatPreview.loadingResolution", key: path, outcome: "memoryMiss")
        }
        if case .image(let image) = state { renderedImagesByItemID[id] = image }
        if case .idle = state { renderedImagesByItemID[id] = nil }
        guard let index = previewItems.firstIndex(where: { $0.id == id }),
              let cell = collectionView.cellForItem(at: IndexPath(item: index, section: 0)) as? ChatImagePreviewCell else {
            if loadingCacheHit != nil { ImageCacheMetrics.shared.mark("chatPreview.loadingDelivery", key: path, outcome: "noCell") }
            return
        }
        if loadingCacheHit != nil { ImageCacheMetrics.shared.mark("chatPreview.loadingDelivery", key: path, outcome: "cell") }
        cell.render(state, memoryCacheHit: loadingCacheHit)
    }

    func currentImages() -> [UIImage?] {
        previewItems.map { renderedImagesByItemID[$0.id] }
    }
    
    func index(at point: CGPoint) -> Int? {
        let p = self.convert(point, to: collectionView)
        return collectionView.indexPathForItem(at: p)?.item
    }
}
