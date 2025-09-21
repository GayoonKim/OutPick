//
//  ChatMessageCollectionView.swift
//  OutPick
//
//  Created by 김가윤 on 3/14/25.
//

import Foundation
import UIKit
import Combine

class ChatMessageCollectionView: UICollectionView {
    let replyPublisher = PassthroughSubject<ChatMessage, Never>()
    let copyPublisher = PassthroughSubject<ChatMessage, Never>()
    let deletePublisher = PassthroughSubject<ChatMessage, Never>()
    let longPressPublisher = PassthroughSubject<IndexPath, Never>()
    
    init() {
        let layout = ChatMessageCollectionView.configureLayout()
        super.init(frame: .zero, collectionViewLayout: layout)

        // cell 등록
        self.register(ChatMessageCell.self, forCellWithReuseIdentifier: ChatMessageCell.reuseIdentifier)
        self.register(DateSeperatorCell.self, forCellWithReuseIdentifier: DateSeperatorCell.reuseIdentifier)
        self.register(readMarkCollectionViewCell.self, forCellWithReuseIdentifier: readMarkCollectionViewCell.reuseIdentifier)
    }
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private static func configureLayout() -> UICollectionViewCompositionalLayout {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(70)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(70)
        )
        let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])
        
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 5
        section.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0)
        
        return UICollectionViewCompositionalLayout(section: section)
    }
    
    // 외부에서 dataSource 설정 가능하도록 노출
    func setCollectionViewDataSource(_ dataSource: UICollectionViewDataSource) {
        self.dataSource = dataSource
    }
    
    func setCollectionViewDelegate(_ delegate: UICollectionViewDelegate) {
        self.delegate = delegate
    }
    
    func scrollToBottom() {
        DispatchQueue.main.async {
            self.layoutIfNeeded()
            
            let lastIndex = self.numberOfItems(inSection: 0) - 1
            let lastIndexPath = IndexPath(item: lastIndex, section: 0)
            
            self.scrollToItem(at: lastIndexPath, at: .bottom, animated: false)
        }
        
    }
    
    @MainActor
    func scrollToMessage(at indexPath: IndexPath) {
        self.layoutIfNeeded()
        self.scrollToItem(at: indexPath, at: .centeredVertically, animated: true)
    }
}

extension UIView {
    var parentViewController: UIViewController? {
        var parentResponder: UIResponder? = self
        while let responder = parentResponder {
            parentResponder = responder.next
            if let vc = parentResponder as? UIViewController {
                return vc
            }
        }
        return nil
    }
}

