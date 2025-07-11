//
//  ChatRoomSettingViewController.swift
//  OutPick
//
//  Created by 김가윤 on 8/5/24.
//

import UIKit
import Combine

class ChatRoomSettingCollectionView: UICollectionViewController, UIGestureRecognizerDelegate, UINavigationControllerDelegate, ChatModalAnimatable {
    
    var interactiveTransition: UIPercentDrivenInteractiveTransition?
    
    private var room: ChatRoom
    private var images: [UIImage]
    private var userProfiles: [UserProfile] = []
    
    private lazy var customNavigationBar: CustomNavigationBarView = {
        let navBar = CustomNavigationBarView()
        navBar.backgroundColor = .clear
        navBar.translatesAutoresizingMaskIntoConstraints = false
        
        return navBar
    }()
    
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
        let layout = Self.configureLayout(self.room)
        super.init(collectionViewLayout: layout)
//        self.userProfiles = ChatUserProfilesStoreManager.shared.getUserProfiles(forRoomName: room.roomName)
        
        Task { @MainActor in
            do {
                self.userProfiles = try GRDBManager.shared.fetchUserProfiles(inRoom: room.roomName)
                self.updateParticipantsSection(with: self.userProfiles)
            } catch {
                
            }
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.backgroundColor = .secondarySystemBackground
        self.attachInteractiveDismissGesture()

        configureCollectionView()
        applyInitialSnapshot()
        setupCustomNavigationBar()
        
        SocketIOManager.shared.listenToNewParticipant()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
    }
    
    func bindImagesPublishers(_ publisher: AnyPublisher<[UIImage], Never>) {
        publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] images in
                guard let self = self else { return }
                self.updateMediaSection(with: images)
            }
            .store(in: &cancellables)
    }
    
//    func bindProfilesPublisher(_ publisher: AnyPublisher<[UserProfile], Never>) {
//        publisher
//            .receive(on: DispatchQueue.main)
//            .sink { [weak self] profiles in
//                guard let self = self else { return }
//                self.updateParticipantsSection(with: profiles)
//            }
//            .store(in: &cancellables)
//    }
//    
    private static func configureLayout(_ room: ChatRoom) -> UICollectionViewCompositionalLayout {
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
                let height: CGFloat = ChatImageStoreManager.shared.getImages(for: room.roomName).count > 0 ? 130 : 44
                
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(height))
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                
                let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(height))
                let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])
                
                let section = NSCollectionLayoutSection(group: group)
                section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 10, bottom: 10, trailing: 10)
                
                return section
                
            case .participantsSection:
                let count = room.participants.count
//                let count = try GRDBManager.shared.fetchUserProfiles(inRoom: room.roomName).count
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
                
                cell.editButtonTapped = { [weak self] in
                    guard let self = self else { return }
                    
                    let editVC = RoomEditViewController(room: self.room)
                    editVC.modalPresentationStyle = .fullScreen
                    
                    self.present(editVC, animated: true, completion: nil)
                }
                
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
    
    private func updateMediaSection(with images: [UIImage]) {
        guard let dataSource = self.dataSource else {
            print("dataSource가 아직 초기화되지 않았습니다.")
            return
        }
        
        var snapshot = dataSource.snapshot()
        snapshot.deleteItems(snapshot.itemIdentifiers(inSection: .mediaSection))
        snapshot.appendItems([.mediaItem(images)], toSection: .mediaSection)
        dataSource.apply(snapshot, animatingDifferences: true)
    }
    
    private func updateParticipantsSection(with userProfiles: [UserProfile]) {
        var snapshot = dataSource.snapshot()
        snapshot.deleteItems(snapshot.itemIdentifiers(inSection: .participantsSection))
        snapshot.appendItems([.participantsItem(userProfiles)], toSection: .participantsSection)
        dataSource.apply(snapshot, animatingDifferences: true)
    }
    
    private func configureCollectionView() {
        collectionView.backgroundColor = .secondarySystemBackground
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(ChatRoomInfoCell.self, forCellWithReuseIdentifier: ChatRoomInfoCell.reuseIdentifier)
        collectionView.register(ChatRoomMediaCollectionViewCell.self, forCellWithReuseIdentifier: ChatRoomMediaCollectionViewCell.reuseIdentifier)
        collectionView.register(ParticipantsSectionParticipantCell.self, forCellWithReuseIdentifier: ParticipantsSectionParticipantCell.reuseIdentifier)
        
        dataSource = configureDataSource()
        collectionView.dataSource = dataSource
    }
    
    private func backButtonTapped() {
        ChatModalTransitionManager.dismiss(from: self)
    }
    
    private func notificationButtonTapped() {
        print(#function)
    }
    
    private func favoriteButtonTapped() {
        print(#function)
    }
    
    private func settingButtonTapped() {
        print(#function)
    }
}

private extension ChatRoomSettingCollectionView {
    @MainActor
    func setupCustomNavigationBar() {
        self.view.addSubview(customNavigationBar)
        
        NSLayoutConstraint.activate([
            customNavigationBar.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            customNavigationBar.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            customNavigationBar.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            
            self.collectionView.topAnchor.constraint(equalTo: customNavigationBar.bottomAnchor),
            self.collectionView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.collectionView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.collectionView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])
        
        configureNavigationBarItems()
    }
    
    private func configureNavigationBarItems() {
        customNavigationBar.configure(
            leftViews: [UIButton.navBackButton(action: backButtonTapped)],
            rightViews: [
                UIButton.navButtonIcon("bell.fill", action: notificationButtonTapped),
                UIButton.navButtonIcon("star", action: favoriteButtonTapped),
                UIButton.navButtonIcon("gearshape", action: settingButtonTapped)
            ]
        )
    }
}
