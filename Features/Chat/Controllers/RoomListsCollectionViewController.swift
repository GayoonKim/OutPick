//
//  ChatCollectionViewController.swift
//  OutPick
//
//  Created by 김가윤 on 8/5/24.
//

import UIKit
import Kingfisher
import FirebaseFirestore

class RoomListsCollectionViewController: UICollectionViewController, UIGestureRecognizerDelegate, ChatModalAnimatable {
    enum Section: Hashable {
        case main
    }

    typealias Item = ChatRoomPreviewItem
    typealias DataSourceType = UICollectionViewDiffableDataSource<Section, Item>

    var chatRooms: [ChatRoomPreviewItem] = []
    var dataSource: DataSourceType!
    private let viewModel: RoomListsViewModel

    // MARK: - Navigation callbacks (Coordinator)
    var onSelectRoom: ((ChatRoom) -> Void)?
    var onCreateRoom: (() -> Void)?
    var onSearchRoom: (() -> Void)?
    
    private let refreshControl: UIRefreshControl = {
        let rc = UIRefreshControl()
        return rc
    }()

    init(
        collectionViewLayout layout: UICollectionViewLayout,
        viewModel: RoomListsViewModel
    ) {
        self.viewModel = viewModel
        super.init(collectionViewLayout: layout)
    }

    required init?(coder: NSCoder) {
        let db = Firestore.firestore()
        let roomRepository = ChatRoomRepository(db: db)
        let useCase = RoomListUseCase(roomRepository: roomRepository)
        self.viewModel = RoomListsViewModel(useCase: useCase)
        super.init(coder: coder)
    }

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

        self.setupNavigationBar()
        self.setupRefreshControl()
        bindViewModel()
        viewModel.notifyCurrentState()
        Task { await viewModel.refreshTopRooms() }
        
        CloudFunctionsManager.shared.callHelloUser(name: "가윤") { result in
            switch result {
            case .success(let message):
                print("함수 결과:", message)  // "Hello, 가윤"
            case .failure(let error):
                print("에러:", error.localizedDescription)
            }
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.onAppear()
    }
    
    @MainActor
    private func setupRefreshControl() {
        collectionView.alwaysBounceVertical = true
        refreshControl.addTarget(self, action: #selector(didPullToRefresh), for: .valueChanged)
        collectionView.refreshControl = refreshControl
    }
    
    @objc private func didPullToRefresh() {
        Task {
            await viewModel.refreshTopRooms()
        }
    }

    private func bindViewModel() {
        viewModel.onStateChanged = { [weak self] state in
            guard let self else { return }
            self.chatRooms = state.rooms
            let itemBySection = [Section.main: state.rooms]
            self.dataSource.applySnapshotUsing(sectionIDs: [Section.main], itemsBySection: itemBySection)
            if !state.isRefreshing {
                self.refreshControl.endRefreshing()
            }
        }
    }

    private func configureDataSource() -> DataSourceType {
        let dataSource = DataSourceType(collectionView: collectionView) { (collectionView, indexPath, item) in
            
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: RoomListCollectionViewCell.identifier, for: indexPath) as! RoomListCollectionViewCell
            cell.backgroundColor = .white
            
            cell.configure(room: item.room, messages: item.messages)

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

        if let onSelectRoom {
            onSelectRoom(selectedItem.room)
            return
        }
        let chatRoomVC = ChatViewController(provider: ChatDependencyContainer.provider)
        if let repositories = ChatDependencyContainer.firebaseRepositories {
            chatRoomVC.injectedFirebaseRepositories = repositories
        }
        chatRoomVC.room = selectedItem.room
        chatRoomVC.configureDefaultViewModelIfNeeded()
        chatRoomVC.isRoomSaving = false
        chatRoomVC.modalPresentationStyle = .fullScreen
        ChatModalTransitionManager.present(chatRoomVC, from: self)
    }

    @objc private func createRoomBtnTapped() {
        if let onCreateRoom {
            onCreateRoom()
            return
        }

        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let chatRoomCreateVC = storyboard.instantiateViewController(identifier: "chatRoomCreateVC") as? RoomCreateViewController else { return }
        chatRoomCreateVC.modalPresentationStyle = .fullScreen
        
        ChatModalTransitionManager.present(chatRoomCreateVC, from: self)
    }
    
    @objc private func searchBtnTapped() {
        if let onSearchRoom {
            onSearchRoom()
            return
        }

        let searchVC = RoomSearchViewController()
        searchVC.modalPresentationStyle = .fullScreen
        ChatModalTransitionManager.present(searchVC, from: self)
    }
}

private extension RoomListsCollectionViewController {
    @MainActor
    func setupNavigationBar() {
        let navBar = CustomNavigationBarView()
        navBar.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(navBar)
        
        let constraints: [NSLayoutConstraint] = [
            navBar.topAnchor.constraint(equalTo: self.view.topAnchor),
            navBar.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            navBar.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            
            self.collectionView.topAnchor.constraint(equalTo: navBar.bottomAnchor),
            self.collectionView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.collectionView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.collectionView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ]

        NSLayoutConstraint.activate(constraints)
        
        navBar.configureForRoomList(target: self, onSearch: #selector(searchBtnTapped), onCreate: #selector(createRoomBtnTapped))
    }
}
