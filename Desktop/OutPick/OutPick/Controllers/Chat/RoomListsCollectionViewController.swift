//
//  ChatCollectionViewController.swift
//  OutPick
//
//  Created by 김가윤 on 8/5/24.
//

import UIKit
import Kingfisher
import Combine

class RoomListsCollectionViewController: CustomTabBarViewController, UIGestureRecognizerDelegate, ChatModalAnimatable {
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
    
    let customTabBar = CustomTabBarView()
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
        
        self.bindPublishers()
        self.updateCollectionView()
        self.setupNavigationBar()
    }

    override func viewController(_ index: Int) -> UIViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        switch index {
        case 0:
            let vc = storyboard.instantiateViewController(withIdentifier: "weatherVC")
            return vc
        case 1:
            let vc = RoomListsCollectionViewController(collectionViewLayout: UICollectionViewFlowLayout())
            return vc
        default:
            return UIViewController()
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
                Task {
                    do {
                        if let cachedImage = KingfisherManager.shared.cache.retrieveImageInMemoryCache(forKey: imagePath) {
                            DispatchQueue.main.async {
                                cell.roomImageView.image = cachedImage
                            }
                        } else {
                            let image = try await FirebaseStorageManager.shared.fetchImageFromStorage(image: imagePath, location: .RoomImage, createdDate: item.room.createdAt)
                            try await KingfisherManager.shared.cache.store(image, forKey: imagePath)
                            DispatchQueue.main.async {
                                cell.roomImageView.image = image
                            }
                        }
                    } catch {
                        print("이미지 로딩 실패: \(error.localizedDescription)")
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
    }

    private func createRoomBtnTapped() {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let chatRoomCreateVC = storyboard.instantiateViewController(identifier: "chatRoomCreateVC") as? RoomCreateViewController else { return }
        chatRoomCreateVC.modalPresentationStyle = .fullScreen
        
        ChatModalTransitionManager.present(chatRoomCreateVC, from: self)
    }
    
    private func searchBtnTapped() {
        print("검색 버튼 탭!")

    }
}

private extension RoomListsCollectionViewController {
    @MainActor
    func setupNavigationBar() {
        let navBar = CustomNavigationBarView()
        navBar.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(navBar)
        
        NSLayoutConstraint.activate([
            navBar.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            navBar.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            navBar.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            navBar.bottomAnchor.constraint(equalTo: self.collectionView.topAnchor),
            
            self.collectionView.topAnchor.constraint(equalTo: navBar.bottomAnchor),
            self.collectionView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.collectionView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.collectionView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])

        navBar.configure(
            leftViews: [UILabel.navTitle("오픈채팅")],
            rightViews: [
                UIButton.navButtonIcon("magnifyingglass") { self.searchBtnTapped() },
                UIButton.navButtonIcon("plus.message.fill") { self.createRoomBtnTapped() },
            ]
        )
    }
}
