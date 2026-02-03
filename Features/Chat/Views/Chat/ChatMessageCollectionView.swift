//
//  ChatImagePreviewCollectionView.swift
//  OutPick
//
//  Created by 김가윤 on 3/14/25.
//

import Foundation
import UIKit
import Combine
import Kingfisher

class ChatMessageCollectionView: UICollectionView {
    let replyPublisher = PassthroughSubject<ChatMessage, Never>()
    let copyPublisher = PassthroughSubject<ChatMessage, Never>()
    let deletePublisher = PassthroughSubject<ChatMessage, Never>()
    let longPressPublisher = PassthroughSubject<IndexPath, Never>()
    
    init() {
        let layout = Self.configureLayout()
        super.init(frame: .zero, collectionViewLayout: layout)

        // cell 등록
        registerCells()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func registerCells() {
        self.register(ChatMessageCell.self, forCellWithReuseIdentifier: ChatMessageCell.reuseIdentifier)
        self.register(DateSeperatorCell.self, forCellWithReuseIdentifier: DateSeperatorCell.reuseIdentifier)
        self.register(readMarkCollectionViewCell.self, forCellWithReuseIdentifier: readMarkCollectionViewCell.reuseIdentifier)
    }
    
    static func configureLayout() -> UICollectionViewCompositionalLayout {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(200)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(200)
        )
        let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])
        
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 10
        section.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0)
        
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
            guard self.numberOfSections > 0 else { return }
            let count = self.numberOfItems(inSection: 0)
            guard count > 0 else { return }
            let lastIndexPath = IndexPath(item: count - 1, section: 0)
            self.scrollToItem(at: lastIndexPath, at: .bottom, animated: false)
        }
    }
    
    @MainActor
    func scrollToMessage(at indexPath: IndexPath) {
        self.layoutIfNeeded()
        guard indexPath.section < self.numberOfSections,
              indexPath.section >= 0,
              indexPath.item >= 0,
              indexPath.item < self.numberOfItems(inSection: indexPath.section) else { return }
        self.scrollToItem(at: indexPath, at: .centeredVertically, animated: true)
    }
}

extension UIView {
    var parentViewController: UIViewController? {
        var responder: UIResponder? = self
        while let r = responder {
            if let vc = r as? UIViewController { return vc }
            responder = r.next
        }
        return nil
    }
}
