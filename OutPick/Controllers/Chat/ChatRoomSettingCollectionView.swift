//
//  ChatRoomSettingViewController.swift
//  OutPick
//
//  Created by 김가윤 on 8/5/24.
//

import UIKit

class ChatRoomSettingCollectionView: UICollectionViewController, UIGestureRecognizerDelegate, UINavigationControllerDelegate {
    
    var interactiveTransition: UIPercentDrivenInteractiveTransition?
    
    private var room: ChatRoom
    private var images: [UIImage]
    
    enum Section: Int, CaseIterable {
        case roomInfoSection
        case mediaSection
//        case participantsSection
    }
    
    enum Item: Hashable {
        case roomInfoItem(ChatRoom)
        case mediaItem([UIImage])
//        case participantsItem
    }
    
    typealias DataSourceType = UICollectionViewDiffableDataSource<Section, Item>
    var dataSource: DataSourceType!
    
    init(room: ChatRoom) {
        self.room = room
        self.images = ChatImageStoreManager.shared.getImages(for: room.roomName)
        
        let layout = Self.configureLayout(room.roomName)
        super.init(collectionViewLayout: layout)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.backgroundColor = .systemGroupedBackground
        self.navigationController?.hidesBottomBarWhenPushed = true
        
        configureCollectionView()
        applyInitialSnapshot()

        // 내비에기션 바 custom back 버튼
        let backButton = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: self, action: #selector(backButtonTapped))
        backButton.tintColor = .black
        self.navigationItem.leftBarButtonItem = backButton
        
        // custom swipe-back 제스처 추가
        self.navigationController?.attachPopGesture(to: self.view)
    }
    
    private static func configureLayout(_ roomName: String) -> UICollectionViewCompositionalLayout {
        return UICollectionViewCompositionalLayout { (sectionIndex: Int, environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? in
            switch Section(rawValue: sectionIndex)! {
            
            case .roomInfoSection:
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(44))
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                
                let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(44))
                let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])
                
                let section = NSCollectionLayoutSection(group: group)
                section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
                
                return section
                
            case .mediaSection:
                let height: CGFloat = ChatImageStoreManager.shared.getImages(for: roomName).count > 0 ? 130 : 44
                
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(height))
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                
                let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(height))
                let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])
                
                let section = NSCollectionLayoutSection(group: group)
                section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10)
                
                return section
            }
        }
    }
    
    private func configureDataSource() -> DataSourceType {
        dataSource = DataSourceType(collectionView: collectionView) { (collectionView, indexPath, item) -> UICollectionViewCell? in
            switch item {
                
            case let .roomInfoItem(room):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ChatRoomInfoCell.reuseIdentifier, for: indexPath) as! ChatRoomInfoCell
                cell.configureCell(room: room)
                
                return cell
             
            case let .mediaItem(images):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ChatRoomMediaCollectionViewCell.reuseIdentifier, for: indexPath) as! ChatRoomMediaCollectionViewCell
                cell.configureCell(for: images)
                
                return cell
            }
        }
        
        return dataSource
    }
    
    private func applyInitialSnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        
        snapshot.appendSections(Section.allCases)
        snapshot.appendItems([.roomInfoItem(self.room)], toSection: .roomInfoSection)
        snapshot.appendItems([.mediaItem(self.images)], toSection: .mediaSection)
        
        dataSource.apply(snapshot, animatingDifferences: false)
    }
    
    private func configureCollectionView() {
        collectionView.backgroundColor = UIColor(white: 0.3, alpha: 0.03)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(ChatRoomInfoCell.self, forCellWithReuseIdentifier: ChatRoomInfoCell.reuseIdentifier)
        collectionView.register(ChatRoomMediaCollectionViewCell.self, forCellWithReuseIdentifier: ChatRoomMediaCollectionViewCell.reuseIdentifier)
        
        dataSource = configureDataSource()
        collectionView.dataSource = dataSource
    }
    
    @objc private func backButtonTapped() {
        self.navigationController?.popViewController(animated: true)
    }
}
