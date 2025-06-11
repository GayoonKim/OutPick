//
//  ChatCollectionViewController.swift
//  OutPick
//
//  Created by 김가윤 on 8/5/24.
//

import UIKit
import Kingfisher
import Combine

class RoomListsCollectionViewController: CustomTabBarViewController, UIGestureRecognizerDelegate, ChatModalPushAnimatable {
    
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
        self.tabBarController?.tabBar.barTintColor = .white
        self.tabBarController?.tabBar.isHidden = false
        
        self.navigationController?.interactivePopGestureRecognizer?.delegate = self
        self.navigationController?.navigationBar.scrollEdgeAppearance?.backgroundColor = .white
        
        dataSource = configureDataSource()
        collectionView.dataSource = dataSource
        collectionView.collectionViewLayout = configureLayout()
        collectionView.backgroundColor = .white
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        
        self.bindPublishers()
        self.updateCollectionView()
        self.setupNavigationBar()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.setNavigationBarHidden(true, animated: false)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
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
        FirebaseManager.shared.$chatRooms
            .receive(on: DispatchQueue.main)
            .sink { [weak self] updatedRooms in
                guard let self = self else { return }
                self.chatRooms = updatedRooms
                self.updateCollectionView()
            }
            .store(in: &cancellables)
    }

    private func updateCollectionView() {
        let chatRoomsList = FirebaseManager.shared.currentChatRooms.sorted(by: <)
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
            if let imageName = item.roomImageName, !imageName.isEmpty {
                Task {
                    do {
                        if let cachedImage = KingfisherManager.shared.cache.retrieveImageInMemoryCache(forKey: imageName) {
                            DispatchQueue.main.async {
                                cell.roomImageView.image = cachedImage
                            }
                        } else {
                            let image = try await FirebaseStorageManager.shared.fetchImageFromStorage(image: imageName, location: .RoomImage, createdDate: item.createdAt)
                            try await KingfisherManager.shared.cache.store(image, forKey: imageName)
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
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, repeatingSubitem: item, count: 1)
        
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
        ChatModalPushTransitionManager.present(chatRoomVC, from: self)
    }

    private func createRoomBtnTapped() {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let chatRoomCreateVC = storyboard.instantiateViewController(identifier: "chatRoomCreateVC") as? RoomCreateViewController else { return }
        chatRoomCreateVC.modalPresentationStyle = .fullScreen

        ChatModalPushTransitionManager.present(chatRoomCreateVC, from: self)
    }
    
    private func searchBtnTapped() {
        print("검색 버튼 탭!")

    }
}

private extension RoomListsCollectionViewController {
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
