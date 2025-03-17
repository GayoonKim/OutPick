//
//  ChatMessageCollectionView.swift
//  OutPick
//
//  Created by 김가윤 on 3/14/25.
//

import Foundation
import UIKit

class ChatMessageCollectionView: UIView {
    enum Section: Hashable {
        case main
    }
    
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, ChatMessage>!
    
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
        collectionView.backgroundColor = .white
        collectionView.register(ChatMessageCell.self, forCellWithReuseIdentifier: ChatMessageCell.resuseIdentifier)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(collectionView)
        
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    private func configureLayout() -> UICollectionViewCompositionalLayout{
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(50))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        
        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(50))
        let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])
        
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 15
        
        return UICollectionViewCompositionalLayout(section: section)
    }
    
    private func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Section, ChatMessage>(collectionView: collectionView) { collectionView, indexPath, message in
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ChatMessageCell.resuseIdentifier, for: indexPath) as! ChatMessageCell
            cell.configure(with: message)
            self.setNeedsLayout()
            self.layoutIfNeeded()
            
            return cell
        }
        
        var snapshot = dataSource.snapshot()
        snapshot.appendSections([Section.main])
        dataSource.apply(snapshot)
    }
    
    private func updateCollectionView(with newMessages: [ChatMessage]) {
        guard !newMessages.isEmpty else { return }
        
        // 새로운 메시지만 추가
        var snapshot = dataSource.snapshot()
        let sortedMessages = newMessages.sorted { $0.sentAt! < $1.sentAt! }
        snapshot.appendItems(sortedMessages, toSection: .main)
        
        dataSource.apply(snapshot) { [weak self] in
            guard let self else { return }
            
            let lastIndex = self.collectionView.numberOfItems(inSection: 0) - 1
            let lastIndexPath = IndexPath(item: lastIndex, section: 0)
            self.collectionView.scrollToItem(at: lastIndexPath, at: .bottom, animated: true)
        }
    }
    
    func addMessages(with newMessages: [ChatMessage]) {
        updateCollectionView(with: newMessages)
    }
}
