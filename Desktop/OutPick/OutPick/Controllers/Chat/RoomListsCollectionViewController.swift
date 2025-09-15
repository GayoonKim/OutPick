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
    
    typealias Item = ChatRoom
    typealias DataSourceType = UICollectionViewDiffableDataSource<Section, Item>
    
    var chatRooms: [ChatRoom] = []
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
            let vc = storyboard.instantiateViewController(withIdentifier: "chatListVC")
            return vc
        default:
            return UIViewController()
        }
    }
    
    private func bindPublishers() {
        // 방 목록 관련
//        FirebaseManager.shared.$chatRooms
////            .receive(on: DispatchQueue.main)
////            
//            .sink { [weak self] updatedRooms in
//                guard let self = self else { return }
//                self.chatRooms = updatedRooms
//                self.updateCollectionView()
//            }
//            .store(in: &cancellables)
        
        
        FirebaseManager.shared.roomChangePublisher
//            .receive(on: DispatchQueue.main)
            .sink { [weak self] updatedRoom in
                guard let self = self else { return }
                print(#function, "✅✅✅✅✅roomChangePublisher 실행✅✅✅✅✅")
                
                if let index = self.chatRooms.firstIndex(where: { $0.ID == updatedRoom.ID }) {
                    self.chatRooms[index] = updatedRoom
                    
                    // Snapshot 업데이트
                    var snapshot = self.dataSource.snapshot()
                    // snapshot 내부에서 기존 item 찾아서 reload
                    if let oldItem = snapshot.itemIdentifiers.first(where: { $0.ID == updatedRoom.ID }) {
                        snapshot.deleteItems([oldItem])
                        snapshot.appendItems([updatedRoom], toSection: .main)
                        self.dataSource.apply(snapshot, animatingDifferences: true)
                    } else {
                        // snapshot에 없다면 append 또는 전체 업데이트 fallback
                        self.updateCollectionView()
                    }
                    self.dataSource.apply(snapshot, animatingDifferences: false)
                }
                
                print(#function, "RoomListsCollectionViewController.swift 방 정보 변경: \(updatedRoom)")
            }
            .store(in: &cancellables)
    }

    private func updateCollectionView() {
//        let chatRoomsList = FirebaseManager.shared.currentChatRooms/*.sorted(by: <)*/
        let chatRoomsList = Array(Set(FirebaseManager.shared.currentChatRooms))
        let itemBySection = [Section.main: chatRoomsList]
        
        dataSource.applySnapshotUsing(sectionIDs: [Section.main], itemsBySection: itemBySection)
    }
    
    private func configureDataSource() -> DataSourceType {
        let dataSource = DataSourceType(collectionView: collectionView) { (collectionView, indexPath, item) in
            
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ChatRoom", for: indexPath) as! RoomListCollectionViewCell
            cell.backgroundColor = .white

            cell.roomImageView.layer.cornerRadius = 15
            cell.roomImageView.clipsToBounds = true
            
            // 기본 이미지 설정
            cell.roomImageView.image = UIImage(named: "Default_Profile")
            
            // 사용자 지정 이미지가 있는 경우에만 이미지 로딩 진행
            if let imagePath = item.roomImagePath, !imagePath.isEmpty {
                Task {
                    do {
                        if let cachedImage = KingfisherManager.shared.cache.retrieveImageInMemoryCache(forKey: imagePath) {
                            DispatchQueue.main.async {
                                cell.roomImageView.image = cachedImage
                            }
                        } else {
                            let image = try await FirebaseStorageManager.shared.fetchImageFromStorage(image: imagePath, location: .RoomImage, createdDate: item.createdAt)
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
            
            cell.roomNameLabel.text = item.roomName
            cell.roomDescriptionLabel.text = item.roomDescription
            
            return cell
        }
        
        return dataSource
    }
    
    private func configureLayout() -> UICollectionViewCompositionalLayout {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        
        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(0.45))
//        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, repeatingSubitem: item, count: 1)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
        
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 5
        
        return UICollectionViewCompositionalLayout(section: section)
    }
    
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let selectedItem = dataSource.itemIdentifier(for: indexPath) else { return }

        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let chatRoomVC = storyboard.instantiateViewController(withIdentifier: "chatRoomVC") as? ChatViewController else { return }
        chatRoomVC.room = selectedItem
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
