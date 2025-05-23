//
//  ChatRoomSettingViewController.swift
//  OutPick
//
//  Created by 김가윤 on 8/5/24.
//

import UIKit
import Combine

class ChatRoomSettingCollectionView: UICollectionViewController, UIGestureRecognizerDelegate, UINavigationControllerDelegate {
    
    var interactiveTransition: UIPercentDrivenInteractiveTransition?
    
    private var room: ChatRoom
    private var images: [UIImage]
    private var userProfiles: [UserProfile] = []
    
    enum Section: Int, CaseIterable {
        case roomInfoSection
        case mediaSection
        case participantsSection
    }
    
    enum Item: Hashable {
        case roomInfoItem(ChatRoom)
        case mediaItem([UIImage])
        case participantsItem([UserProfile])
    }
    
    typealias DataSourceType = UICollectionViewDiffableDataSource<Section, Item>
    var dataSource: DataSourceType!
    
    private var cancellables = Set<AnyCancellable>()
    
    init(room: ChatRoom) {
        self.room = room
        self.images = ChatImageStoreManager.shared.getImages(for: room.roomName)
        self.userProfiles = ChatUserProfilesStoreManager.shared.getUserProfiles(forRoomName: room.roomName)
        
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
    
    func bindPublishers(_ publisher: AnyPublisher<[UIImage], Never>) {
        publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] images in
                self?.updateMediaSection(with: images)
            }
            .store(in: &cancellables)
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
                section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 10, bottom: 10, trailing: 10)
                
                return section
                
            case .participantsSection:
                let count = ChatUserProfilesStoreManager.shared.countProfiles(for: roomName)
                let rowCount = ceil(Double(count) / 1.0) // 한 줄에 1명 보여주는 구성일 경우
                let itemHeight: CGFloat = 53
                let spacing: CGFloat = 5
                let headerHeight: CGFloat = 40 // "대화상대 (n명)" 라벨
                let showAllButtonHeight: CGFloat = count > 50 ? 44 : 0
                
                let totalHeight = CGFloat(rowCount) * itemHeight +
                CGFloat(max(0, rowCount - 1)) * spacing +
                headerHeight + showAllButtonHeight
                
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(totalHeight))
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                
                let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(totalHeight))
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
                
                
            case let .participantsItem(userProfiles):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ParticipantsSectionParticipantCell.reuseIdentifier, for: indexPath) as! ParticipantsSectionParticipantCell
                cell.configureCell(userProfiles)
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
        snapshot.appendItems([.participantsItem(self.userProfiles)], toSection: .participantsSection)
        
        dataSource.apply(snapshot, animatingDifferences: false)
    }
    
    func updateMediaSection(with images: [UIImage]) {
        var snapshot = dataSource.snapshot()
        snapshot.appendItems([.mediaItem(images)], toSection: .mediaSection)
        dataSource.apply(snapshot, animatingDifferences: true)
    }
    
    private func configureCollectionView() {
        collectionView.backgroundColor = UIColor(white: 0.3, alpha: 0.03)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(ChatRoomInfoCell.self, forCellWithReuseIdentifier: ChatRoomInfoCell.reuseIdentifier)
        collectionView.register(ChatRoomMediaCollectionViewCell.self, forCellWithReuseIdentifier: ChatRoomMediaCollectionViewCell.reuseIdentifier)
        collectionView.register(ParticipantsSectionParticipantCell.self, forCellWithReuseIdentifier: ParticipantsSectionParticipantCell.reuseIdentifier)
        
        dataSource = configureDataSource()
        collectionView.dataSource = dataSource
    }
    
    @objc private func backButtonTapped() {
        self.navigationController?.popViewController(animated: true)
    }
}
