//
//  ChatRoomSettingViewController.swift
//  OutPick
//
//  Created by 김가윤 on 8/5/24.
//

import UIKit
import Combine
import GRDB
import Kingfisher

class ChatRoomSettingCollectionView: UICollectionViewController, UIGestureRecognizerDelegate, UINavigationControllerDelegate/*, ChatModalAnimatable*/ {
    
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
    
    var onRoomUpdated: ((ChatRoom) -> Void)?
    
    init(room: ChatRoom, profiles: [UserProfile], images: [UIImage]) {
        self.room = room
        self.userProfiles = profiles
        self.images = images
        let layout = Self.configureLayout(self.room, userProfiles: self.userProfiles, images: self.images)
        super.init(collectionViewLayout: layout)
        
        Task { @MainActor in
            self.updateMediaSection()
            self.observeRoomImages(for: self.room.ID ?? "")
            self.observeParticipants()
            self.observeRoomInfo()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        print("💧 ChatViewController deinit")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.backgroundColor = .secondarySystemBackground

        configureCollectionView()
        applyInitialSnapshot()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cancellables.removeAll()
    }
    
    private func observeRoomImages(for roomID: String) {
        let observation = ValueObservation.tracking { db in
            print("🔄 roomImage 테이블 변경 감지")
            return try Row.fetchAll(
                db,
                sql: "SELECT rowid, imageName FROM roomImage WHERE roomId = ? ORDER BY uploadedAt",
                arguments: [roomID]
            )
            .compactMap { row in
                row["imageName"] as? String
            }
        }
        
        observation
            .publisher(in: GRDBManager.shared.dbPool, scheduling: .async(onQueue: .main))
            .sink(
                receiveCompletion: { completion in
                    if case let .failure(error) = completion {
                        print("roomImage 관찰 에러:", error)
                    }
                },
                receiveValue: { [weak self] imageNames in
                    guard let self = self else { return }
                    
                    Task { @MainActor in
                        var images = [UIImage]()
                        for name in imageNames {
                            if let image = await KingFisherCacheManager.shared.loadImage(named: name) {
                                images.append(image)
                            }
                        }
                        
                        self.images = images
                        self.updateMediaSection()
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    private func observeRoomInfo() {
        FirebaseManager.shared.roomChangePublisher
            .receive(on: DispatchQueue.main)
            .filter{ [weak self] updatedRoom in
                guard let self = self else { return false }
                
                return updatedRoom.ID == self.room.ID
            }
            .sink { [weak self] updatedRoom in
                guard let self = self  else { return }
                
                guard self.isViewLoaded, self.view.window != nil else {
                    print("⚠️ UI 없음. 업데이트 무시")
                    return
                }
                
                self.room = updatedRoom
                self.updateRoomInfoSection()
                
            }
            .store(in: &cancellables)
    }
    
    private func observeParticipants() {
        let observation = ValueObservation.tracking { db in
            let sql = """
                    SELECT DISTINCT userProfile.*
                    FROM userProfile
                    JOIN roomParticipant ON userProfile.email = roomParticipant.email
                    WHERE roomParticipant.roomId = ?
                    ORDER BY userProfile.nickname
                    """
            return try UserProfile.fetchAll(db, sql: sql, arguments: [self.room.ID ?? ""])
        }
        
        observation
            .publisher(in: GRDBManager.shared.dbPool, scheduling: .async(onQueue: .main))
            .sink(receiveCompletion: { completion in
                switch completion {
                case .finished:
                    print("Participants observation completed normally")
                case .failure(let error):
                    print("Participants observation error: \(error)")
                }
            }, receiveValue: { [weak self] profiles in
                guard let self = self else { return }
                print("새로운 참여자 프로필 업데이트:", profiles.map { $0.nickname })
                self.userProfiles = profiles
                self.updateParticipantsSection(with: self.userProfiles)
            })
            .store(in: &cancellables)
    }
    
    private static func configureLayout(_ room: ChatRoom, userProfiles: [UserProfile], images: [UIImage]) -> UICollectionViewCompositionalLayout {
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
                let height: CGFloat = images.count > 0 ? 130 : 44
                
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(height))
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                
                let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(height))
                let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])
                
                let section = NSCollectionLayoutSection(group: group)
                section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 10, bottom: 10, trailing: 10)
                
                return section
                
            case .participantsSection:
                let count = userProfiles.count
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
                    
                    editVC.onCompleteEdit = { [weak self] selectedImage, newName, newDesc in
                        guard let self = self else { return }
                        
                        var newImagePath: String? = nil
                        if let image = selectedImage {
                            if let pathToRemove = self.room.roomImagePath {
                                FirebaseStorageManager.shared.deleteImageFromStorage(path: pathToRemove)
                            }
                            
                            let pathToAdd = try await FirebaseStorageManager.shared.uploadImageToStorage(image: image, location: .RoomImage, roomName: room.roomName)
                            KingFisherCacheManager.shared.storeImage(image, forKey: pathToAdd)
                            newImagePath = pathToAdd
                        }
                        
                        if let path = newImagePath {
                            self.room.roomImagePath = path
                        }
                        self.room.roomName = newName
                        self.room.roomDescription = newDesc
                        try await FirebaseManager.shared.updateRoomInfo(room: self.room, newImagePath: self.room.roomImagePath ?? "", roomName: newName, roomDescription: newDesc)

                        self.updateRoomInfoSection()
                        self.onRoomUpdated?(self.room)
                    }
                    
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
    
    private func updateRoomInfoSection() {
        var snapshot = dataSource.snapshot()
        snapshot.deleteItems(snapshot.itemIdentifiers(inSection: .roomInfoSection))
        snapshot.appendItems([.roomInfoItem(self.room)], toSection: .roomInfoSection)
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self = self else { return }
            // roomInfoItem 셀 찾아서 강제로 업데이트
            if let indexPath = self.dataSource.indexPath(for: .roomInfoItem(self.room)),
               let cell = self.collectionView.cellForItem(at: indexPath) as? ChatRoomInfoCell {
                cell.configureCell(room: self.room)
            }
        }
    }
    
    private func updateMediaSection() {
        guard let dataSource = self.dataSource else {
            print("dataSource가 아직 초기화되지 않았습니다.")
            return
        }
        
        var snapshot = dataSource.snapshot()
        snapshot.deleteItems(snapshot.itemIdentifiers(inSection: .mediaSection))
        snapshot.appendItems([.mediaItem(self.images)], toSection: .mediaSection)
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self = self else { return }
            
            self.collectionView.setCollectionViewLayout(Self.configureLayout(self.room, userProfiles: self.userProfiles, images: self.images), animated: false)
            if let indexPath = self.dataSource.indexPath(for: .mediaItem(self.images)),
               let cell = self.collectionView.cellForItem(at: indexPath) as? ChatRoomMediaCollectionViewCell {
                cell.configureCell(for: images)
            }
        }
    }
    
    @MainActor
    private func updateParticipantsSection(with userProfiles: [UserProfile]) {
        print(#function, "호출되었습니다.", userProfiles)
        var snapshot = dataSource.snapshot()
        snapshot.deleteItems(snapshot.itemIdentifiers(inSection: .participantsSection))
        snapshot.appendItems([.participantsItem(userProfiles)], toSection: .participantsSection)
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self = self else { return }
            // layout을 새로 할당!
            self.collectionView.setCollectionViewLayout(Self.configureLayout(self.room, userProfiles: userProfiles, images: self.images), animated: false)
            if let indexPath = self.dataSource.indexPath(for: .participantsItem(userProfiles)),
               let cell = self.collectionView.cellForItem(at: indexPath) as? ParticipantsSectionParticipantCell {
                cell.configureCell(userProfiles)
            }
        }
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
