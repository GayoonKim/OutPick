//
//  ChatCollectionViewController.swift
//  OutPick
//
//  Created by 김가윤 on 8/5/24.
//

import UIKit
import Kingfisher
import Combine

class RoomListsCollectionViewController: UICollectionViewController, UIGestureRecognizerDelegate, ChatModalAnimatable {
    enum Section: Hashable {
        case main
    }
    
    struct RoomPreview: Hashable {
        let room: ChatRoom
        let messages: [ChatMessage]
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(room.ID)
        }
        
        static func == (lhs: RoomPreview, rhs: RoomPreview) -> Bool {
            return lhs.room.ID == rhs.room.ID
        }
    }

    typealias Item = RoomPreview
    typealias DataSourceType = UICollectionViewDiffableDataSource<Section, Item>

    var chatRooms: [RoomPreview] = []
    var dataSource: DataSourceType!
    
    private lazy var cancellables = Set<AnyCancellable>()

    private var tabViewControllers: [Int: UIViewController] = [:]
    private var currentChildViewController: UIViewController?
    private var currentTabIndex: Int?

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .white
        
        self.attachInteractiveDismissGesture()
        
        dataSource = configureDataSource()
        collectionView.register(RoomListCollectionViewCell.self, forCellWithReuseIdentifier: RoomListCollectionViewCell.identifier)
        collectionView.dataSource = dataSource
        collectionView.collectionViewLayout = configureLayout()
        collectionView.backgroundColor = .white
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.contentInsetAdjustmentBehavior = .never
        
        self.bindPublishers()
        self.updateCollectionView()
        self.setupNavigationBar()
        

    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let profile = LoginManager.shared.currentUserProfile {
            print(#function, "currentUserProfile: \(profile)")
        }
    }

    private func bindPublishers() {
        // 방 목록 관련
        FirebaseManager.shared.$hotRoomsWithPreviews
            .subscribe(on: DispatchQueue.global(qos: .userInitiated)) // ⬅️ 백그라운드에서 변환
            .map { (pairs: [(ChatRoom, [ChatMessage])]) -> [RoomPreview] in
                pairs.map { RoomPreview(room: $0.0, messages: $0.1) }
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] updatedRooms in
                guard let self = self else { return }
                self.chatRooms = updatedRooms
                self.updateCollectionView()
            }
            .store(in: &cancellables)
    }

    @MainActor
    private func updateCollectionView() {
        let chatRoomsList = chatRooms
        let itemBySection = [Section.main: chatRoomsList]
        dataSource.applySnapshotUsing(sectionIDs: [Section.main], itemsBySection: itemBySection)
    }
    
    private func configureDataSource() -> DataSourceType {
        let dataSource = DataSourceType(collectionView: collectionView) { (collectionView, indexPath, item) in
            
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: RoomListCollectionViewCell.identifier, for: indexPath) as! RoomListCollectionViewCell
            cell.backgroundColor = .white
            
            cell.configure(room: item.room, messages: item.messages)
            if let imagePath = item.room.roomImagePath, !imagePath.isEmpty {
                Task.detached(priority: .userInitiated) { [weak self, weak cell] in
                    guard let self = self, let cell = cell else { return }
                    do {
                        let image = try await KingFisherCacheManager.shared.loadOrFetchImage(forKey: imagePath) {
                            try await FirebaseStorageManager.shared.fetchImageFromStorage(image: imagePath, location: .RoomImage)
                        }
                        
                        if await self.collectionView.indexPath(for: cell) == indexPath {
                            await MainActor.run {
                                cell.roomImageView.image = image
                            }
                        }
                    } catch {
                        
                    }
                }
            }

            return cell
        }
        
        return dataSource
    }
    
    private func configureLayout() -> UICollectionViewCompositionalLayout {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(200)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(200)
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
        
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 5
        
        return UICollectionViewCompositionalLayout(section: section)
    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let selectedItem = dataSource.itemIdentifier(for: indexPath) else { return }

        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let chatRoomVC = storyboard.instantiateViewController(withIdentifier: "chatRoomVC") as? ChatViewController else { return }
        chatRoomVC.room = selectedItem.room
        chatRoomVC.isRoomSaving = false
        chatRoomVC.modalPresentationStyle = .fullScreen
        ChatModalTransitionManager.present(chatRoomVC, from: self)
//        chatRoomVC.hidesBottomBarWhenPushed = true
//        self.navigationController?.pushViewController(chatRoomVC, animated: true)
    }

    @objc private func createRoomBtnTapped() {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let chatRoomCreateVC = storyboard.instantiateViewController(identifier: "chatRoomCreateVC") as? RoomCreateViewController else { return }
        chatRoomCreateVC.modalPresentationStyle = .fullScreen
        
        ChatModalTransitionManager.present(chatRoomCreateVC, from: self)
//        chatRoomCreateVC.hidesBottomBarWhenPushed = true
//        self.navigationController?.pushViewController(chatRoomCreateVC, animated: true)
    }
    
    @objc private func searchBtnTapped() {
        print("검색 버튼 탭!")
    }
}

private extension RoomListsCollectionViewController {
    @MainActor
    func setupNavigationBar() {
        let navBar = CustomNavigationBarView()
        navBar.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(navBar)
        
        var constraints: [NSLayoutConstraint] = [
            navBar.topAnchor.constraint(equalTo: self.view.topAnchor),
            navBar.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            navBar.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            
            self.collectionView.topAnchor.constraint(equalTo: navBar.bottomAnchor),
            self.collectionView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.collectionView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.collectionView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ]
//
//        if customTabBar.superview != nil {
//            constraints.append(self.collectionView.bottomAnchor.constraint(equalTo: self.customTabBar.topAnchor))
//        } else {
//            constraints.append(self.collectionView.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor))
//        }
        NSLayoutConstraint.activate(constraints)
        
        navBar.configureForRoomList(target: self, onSearch: #selector(searchBtnTapped), onCreate: #selector(createRoomBtnTapped))
    }
}
