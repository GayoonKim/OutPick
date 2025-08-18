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
    
    enum Item: Hashable {
        case message(ChatMessage)
        case dateSeparator(Date)
        case readMarker
    }
    
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    
    private var lastMessageDate: Date?
    private var lastReadMessageID: String?
    func setLastReadMessageID(_ id: String?) {
        self.lastReadMessageID = id
    }
    
    var isUserInCurrentRoom = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setupCollectionView()
        configureDataSource()
        applySnapshot([])
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
    
    private func configureDataSource() {
        print(#function)
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in

            switch item {
            case .message(let message):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ChatMessageCell.reuseIdentifier, for: indexPath) as! ChatMessageCell
                
                if message.attachments.isEmpty {
                    cell.configureWithMessage(with: message)
                } else {
                    cell.configureWithImage(with: message)
                }
                
                return cell
                
            case .dateSeparator(let date):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: DateSeperatorCell.reuseIdentifier, for: indexPath) as! DateSeperatorCell
                
                let dateText = self.formatDateToDayString(date)
                cell.configureWithDate(dateText)
                
                return cell
                
            case .readMarker:
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: readMarkCollectionViewCell.reuseIdentifier, for: indexPath) as! readMarkCollectionViewCell
                
                cell.configure()
                return cell
            }
        }
        
    }
    
    private func updateCollectionView(with newItems: [Item]) {
//        print("************************ \(#function) 호출 ************************")
        
        var snapshot = dataSource.snapshot()
        snapshot.appendItems(newItems, toSection: .main)
        
//        print("Before apply, snapshot items: \(snapshot.itemIdentifiers)") // 추가된 아이템 확인
        
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self = self else { return }
            
//            print("************************ Apply 완료, snapshot items: \(snapshot.itemIdentifiers) ************************")
            
            DispatchQueue.main.async {
                self.collectionView.layoutIfNeeded()
                
                let lastIndex = self.collectionView.numberOfItems(inSection: 0) - 1
                let lastIndexPath = IndexPath(item: lastIndex, section: 0)
                
                self.collectionView.scrollToItem(at: lastIndexPath, at: .bottom, animated: false)
            }
        }
    }
    
    func applySnapshot(_ items: [Item]) {
        var snapshot = dataSource.snapshot()
        if snapshot.sectionIdentifiers.isEmpty { snapshot.appendSections([Section.main]) }
        snapshot.appendItems(items, toSection: .main)
        
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.collectionView.layoutIfNeeded()
                
                let lastIndex = self.collectionView.numberOfItems(inSection: 0) - 1
                let lastIndexPath = IndexPath(item: lastIndex, section: 0)
                
                self.collectionView.scrollToItem(at: lastIndexPath, at: .bottom, animated: false)
            }
        }
    }

    func addMessages(_ messages: [ChatMessage], isNew: Bool) {
        print("************************ \(#function) 호출 ************************")
        
        var items: [Item] = []
        
        let snapshot = dataSource.snapshot()
        let existingIDs = snapshot.itemIdentifiers.compactMap { item -> String? in
            if case .message(let m) = item { return m.ID }
            return nil
        }
        
        let newMessages = messages.filter { !existingIDs.contains($0.ID) }

        let hasReadMarker = snapshot.itemIdentifiers.contains { item in
            if case .readMarker = item { return true }
            return false
        }

//        if !hasReadMarker, let lastMessageID = self.lastReadMessageID,
//           let firstMessage = newMessages.first,
//           firstMessage.ID != lastMessageID {
//            items.append(.readMarker)
//        }

        for message in newMessages {
            let messageDate = Calendar.current.startOfDay(for: message.sentAt ?? Date())
            
            if lastMessageDate == nil || lastMessageDate! != messageDate {
                items.append(.dateSeparator(message.sentAt ?? Date()))
                lastMessageDate = messageDate
            }
            
            items.append(.message(message))
        }
        
        updateCollectionView(with: items)

        if !hasReadMarker, let lastMessageID = self.lastReadMessageID, !isUserInCurrentRoom, isNew,
           let firstMessage = newMessages.first,
           firstMessage.ID != lastMessageID {
            
            var updatedSnapshot = dataSource.snapshot()
            let firstNewItem = items.first(where: {
                if case .message = $0 { return true }
                return false
            })
            
            if let firstNewItem = firstNewItem {
                updatedSnapshot.insertItems([.readMarker], beforeItem: firstNewItem)
                dataSource.apply(updatedSnapshot, animatingDifferences: false)
            }
        }
        
    }
    
    private func formatDateToDayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.dateFormat = "yyyy년 M월 d일 EEEE"
        return formatter.string(from: date)
    }
    
    func scrollToBottom() {
        DispatchQueue.main.async {
            self.collectionView.layoutIfNeeded()
            
            let lastIndex = self.collectionView.numberOfItems(inSection: 0) - 1
            let lastIndexPath = IndexPath(item: lastIndex, section: 0)
            
            self.collectionView.scrollToItem(at: lastIndexPath, at: .bottom, animated: false)
        }
    }
    
}
