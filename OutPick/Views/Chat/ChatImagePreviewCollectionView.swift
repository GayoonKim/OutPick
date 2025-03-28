//
//  ChatImagePreviewCollectionView.swift
//  OutPick
//
//  Created by 김가윤 on 3/28/25.
//

import Foundation
import UIKit

protocol ChatImagePreviewCollectionViewDelegate: AnyObject {
    func ChatImagePreviewCollectionView(_ collectionView: ChatImagePreviewCollectionView, didRemoveImageAt index: Int)
}

class ChatImagePreviewCollectionView: UIView {
    enum Section: Hashable {
        case main
    }
    
    weak var delegate: ChatImagePreviewCollectionViewDelegate?
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, UIImage>!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setupCollectionView()
        configureDataSource()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupCollectionView() {
        let layout = configureLayout()
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.isScrollEnabled = false
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
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
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .estimated(80),
            heightDimension: .estimated(80)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .fractionalHeight(1)
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, repeatingSubitem: item, count: 3)
        
        let section = NSCollectionLayoutSection(group: group)
        return UICollectionViewCompositionalLayout(section: section)
    }
    
    private func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { [weak self] collectionView, indexPath, image in
            guard let self = self else { return nil}
            
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ChatImagePreviewCell.reuseIdentifier, for: indexPath) as! ChatImagePreviewCell
            cell.configure(with: image)
            
            return cell
        }
        
        var snapshot = NSDiffableDataSourceSnapshot<Section, UIImage>()
        snapshot.appendSections([Section.main])
        dataSource.apply(snapshot, animatingDifferences: false)
    }
    
    func updateCollectionView(with images: [UIImage]) {
        let itemBySection = [Section.main: images]
        dataSource.applySnapshotUsing(sectionIDs: [Section.main], itemsBySection: itemBySection)
    }
}

extension ChatImagePreviewCollectionView: UICollectionViewDelegate {
    func ChatImagePreviewCollectionView(_ collectionView: ChatImagePreviewCollectionView, didRemoveImageAt index: Int) {
        
    }
}
