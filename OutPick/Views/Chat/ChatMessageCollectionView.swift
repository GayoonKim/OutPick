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
        
        let image1 = UIImage(systemName: "chevron.compact.down")
        if let imageData = image1?.jpegData(compressionQuality: 1) {
            let a1 = Attachment(type: .image, fileName: UUID().uuidString, fileData: imageData)
            let a2 = Attachment(type: .image, fileName: UUID().uuidString, fileData: imageData)
            let a3 = Attachment(type: .image, fileName: UUID().uuidString, fileData: imageData)
            let a4 = Attachment(type: .image, fileName: UUID().uuidString, fileData: imageData)
            let a5 = Attachment(type: .image, fileName: UUID().uuidString, fileData: imageData)
            let a6 = Attachment(type: .image, fileName: UUID().uuidString, fileData: imageData)
            let a7 = Attachment(type: .image, fileName: UUID().uuidString, fileData: imageData)
            let a8 = Attachment(type: .image, fileName: UUID().uuidString, fileData: imageData)
            let a9 = Attachment(type: .image, fileName: UUID().uuidString, fileData: imageData)
            let a10 = Attachment(type: .image, fileName: UUID().uuidString, fileData: imageData)
            let message = ChatMessage(roomName: "Test", senderID: "example@example.com", senderNickname: "김가윤", msg: "", sentAt: Date(), attachments: [a1,a2,a3,a4,a5,a6,a7,a8,a9,a10])
            self.updateCollectionView(with: message)
        }
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
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    
    private func configureLayout() -> UICollectionViewCompositionalLayout {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(100)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(100)
        )
        let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])
        
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 12
        section.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0)
        
        return UICollectionViewCompositionalLayout(section: section)
    }
    
    private func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Section, ChatMessage>(collectionView: collectionView) { collectionView, indexPath, message in
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ChatMessageCell.resuseIdentifier, for: indexPath) as! ChatMessageCell
            cell.prepareForReuse()
            
            if let _ = message.attachments {
                cell.configureWithImage(with: message)
            } else {
                cell.configureWithMessage(with: message)
            }
            
            return cell
        }
        
        var snapshot = dataSource.snapshot()
        snapshot.appendSections([Section.main])
        dataSource.apply(snapshot)
    }
    
    private func updateCollectionView(with newMessage: ChatMessage) {
        var snapshot = dataSource.snapshot()
        snapshot.appendItems([newMessage], toSection: .main)
        
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self = self else { return }
            
            self.collectionView.layoutIfNeeded()
            
            let lastIndex = self.collectionView.numberOfItems(inSection: 0) - 1
            let lastIndexPath = IndexPath(item: lastIndex, section: 0)
            
            self.collectionView.scrollToItem(at: lastIndexPath, at: .bottom, animated: false)
        }
    }
    
    func addMessages(with newMessage: ChatMessage) {
        updateCollectionView(with: newMessage)
    }
}
