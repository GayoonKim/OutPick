//
//  ChatMessageCollectionView.swift
//  OutPick
//
//  Created by 김가윤 on 3/14/25.
//

import Foundation
import UIKit
import Combine

class ChatMessageCollectionView: UIView {
    private(set) var collectionView: UICollectionView!
//    private var highlightedCell: ChatMessageCell?
    private var cancellables = Set<AnyCancellable>()

    let replyPublisher = PassthroughSubject<ChatMessage, Never>()
    let copyPublisher = PassthroughSubject<ChatMessage, Never>()
    let deletePublisher = PassthroughSubject<ChatMessage, Never>()
    let longPressPublisher = PassthroughSubject<IndexPath, Never>()

    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setupCollectionView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupCollectionView() {
        let layout = configureLayout()
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.register(ChatMessageCell.self, forCellWithReuseIdentifier: ChatMessageCell.reuseIdentifier)
        collectionView.register(DateSeperatorCell.self, forCellWithReuseIdentifier: DateSeperatorCell.reuseIdentifier)
        collectionView.register(readMarkCollectionViewCell.self, forCellWithReuseIdentifier: readMarkCollectionViewCell.reuseIdentifier)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(collectionView)
        
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 8),
            collectionView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -8),
            collectionView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -8),
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
        section.interGroupSpacing = 5
        section.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0)
        
        return UICollectionViewCompositionalLayout(section: section)
    }
    
    // 외부에서 dataSource 설정 가능하도록 노출
    func setCollectionViewDataSource(_ dataSource: UICollectionViewDataSource) {
        collectionView.dataSource = dataSource
    }
    
    func setCollectionViewDelegate(_ delegate: UICollectionViewDelegate) {
        collectionView.delegate = delegate
    }
    
    func reloadData() {
        collectionView.reloadData()
    }
    
    func scrollToBottom() {
        DispatchQueue.main.async {
            self.collectionView.layoutIfNeeded()
            
            let lastIndex = self.collectionView.numberOfItems(inSection: 0) - 1
            let lastIndexPath = IndexPath(item: lastIndex, section: 0)
            
            self.collectionView.scrollToItem(at: lastIndexPath, at: .bottom, animated: false)
        }
    }
    
    @MainActor
    func scrollToMessage(at indexPath: IndexPath) {
        self.collectionView.layoutIfNeeded()
        self.collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: true)
    }

//    func setHighlightedCell(_ cell: ChatMessageCell?) {
//        highlightedCell?.setHightlightedOverlay(false) // 기존 강조 해제
//        highlightedCell = cell
//        cell?.setHightlightedOverlay(true)           // 새로 강조
//    }
//
//    func clearHighlightedCell() {
//        highlightedCell?.setHightlightedOverlay(false)
//        highlightedCell = nil
//    }
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
