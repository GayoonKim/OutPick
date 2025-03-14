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
    private var messages: [ChatMessage] = []
    
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
        collectionView.backgroundColor = .systemPink
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
            
            return cell
        }
        
        updateCollectionView()
    }
    
    private func updateCollectionView() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, ChatMessage>()
        snapshot.appendSections([.main])
        snapshot.appendItems(messages)
        
        dataSource.apply(snapshot, animatingDifferences: true)
    }
    
    func addMessages(with messages: [ChatMessage]) {
        self.messages = messages
        updateCollectionView()
    }
}
