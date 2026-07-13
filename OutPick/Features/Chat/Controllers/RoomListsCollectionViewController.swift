//
//  ChatCollectionViewController.swift
//  OutPick
//
//  Created by 김가윤 on 8/5/24.
//

import UIKit
import Kingfisher

class RoomListsCollectionViewController: UICollectionViewController, UIGestureRecognizerDelegate, UICollectionViewDataSourcePrefetching, ChatModalAnimatable {
    enum Section: Hashable {
        case main
    }

    typealias Item = ChatRoomPreviewItem
    typealias DataSourceType = UICollectionViewDiffableDataSource<Section, Item>

    var chatRooms: [ChatRoomPreviewItem] = []
    var dataSource: DataSourceType!
    private let viewModel: RoomListsViewModel
    private let currentUserProvider: any CurrentUserProviding
    private let roomImageManager: RoomImageManaging
    private let avatarImageManager: AvatarImageManaging
    private var imagePrefetchTasks: [IndexPath: Task<Void, Never>] = [:]

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
        viewModel: RoomListsViewModel,
        currentUserProvider: any CurrentUserProviding,
        roomImageManager: RoomImageManaging,
        avatarImageManager: AvatarImageManaging
    ) {
        self.viewModel = viewModel
        self.currentUserProvider = currentUserProvider
        self.roomImageManager = roomImageManager
        self.avatarImageManager = avatarImageManager
        super.init(collectionViewLayout: layout)
    }

    required init?(coder: NSCoder) {
        fatalError("Storyboard initialization is no longer supported for RoomListsCollectionViewController.")
    }

    deinit {
        imagePrefetchTasks.values.forEach { $0.cancel() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = OutPickTheme.ColorToken.backgroundBase
        
        dataSource = configureDataSource()
        collectionView.register(RoomListCollectionViewCell.self, forCellWithReuseIdentifier: RoomListCollectionViewCell.identifier)
        collectionView.dataSource = dataSource
        collectionView.prefetchDataSource = self
        collectionView.collectionViewLayout = configureLayout()
        collectionView.backgroundColor = OutPickTheme.ColorToken.backgroundBase
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.contentInsetAdjustmentBehavior = .never

        self.setupNavigationBar()
        self.setupRefreshControl()
        bindViewModel()
        viewModel.notifyCurrentState()
        Task { await viewModel.loadInitiallyIfNeeded() }
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
            cell.backgroundColor = OutPickTheme.ColorToken.backgroundBase
            
            cell.configure(
                room: item.room,
                messages: item.messages,
                currentUserUID: self.currentUserProvider.canonicalUserID,
                roomImageManager: self.roomImageManager,
                avatarImageManager: self.avatarImageManager
            )

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
        guard let onSelectRoom else {
            assertionFailure("RoomListsCollectionViewController requires coordinator-owned room routing.")
            return
        }
        onSelectRoom(selectedItem.room)
    }

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let items = indexPaths.compactMap { indexPath -> (IndexPath, ChatRoomPreviewItem)? in
            guard let item = dataSource.itemIdentifier(for: indexPath) else { return nil }
            return (indexPath, item)
        }

        for (indexPath, item) in items {
            guard imagePrefetchTasks[indexPath] == nil else { continue }

            let roomPaths = roomCoverPaths(from: [item])
            let avatarPaths = senderAvatarPaths(from: [item])
            guard !roomPaths.isEmpty || !avatarPaths.isEmpty else { continue }

            let roomImageManager = self.roomImageManager
            let avatarImageManager = self.avatarImageManager
            imagePrefetchTasks[indexPath] = Task { [weak self] in
                await roomImageManager.prefetchImages(
                    paths: roomPaths,
                    maxBytes: 3 * 1024 * 1024,
                    maxConcurrent: 2
                )
                await avatarImageManager.prefetchAvatars(
                    paths: avatarPaths,
                    maxBytes: 2 * 1024 * 1024,
                    maxConcurrent: 3
                )
                await MainActor.run {
                    self?.imagePrefetchTasks[indexPath] = nil
                }
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            imagePrefetchTasks[indexPath]?.cancel()
            imagePrefetchTasks[indexPath] = nil
        }
    }

    @objc private func createRoomBtnTapped() {
        guard let onCreateRoom else {
            assertionFailure("RoomListsCollectionViewController requires coordinator-owned room creation routing.")
            return
        }
        onCreateRoom()
    }
    
    @objc private func searchBtnTapped() {
        guard let onSearchRoom else {
            assertionFailure("RoomListsCollectionViewController requires coordinator-owned room search routing.")
            return
        }
        onSearchRoom()
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
            self.collectionView.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor)
        ]

        NSLayoutConstraint.activate(constraints)
        
        navBar.configureForRoomList(target: self, onSearch: #selector(searchBtnTapped), onCreate: #selector(createRoomBtnTapped))
    }

    func roomCoverPaths(from items: [ChatRoomPreviewItem]) -> [String] {
        Array(Set(items.compactMap { item in
            guard let path = item.room.coverImagePath, !path.isEmpty else { return nil }
            return path
        }))
    }

    func senderAvatarPaths(from items: [ChatRoomPreviewItem]) -> [String] {
        let currentUserUID = currentUserProvider.canonicalUserID
        let paths = items.flatMap(\.messages).compactMap { message -> String? in
            guard message.senderUID != currentUserUID,
                  let path = message.senderAvatarPath,
                  !path.isEmpty else { return nil }
            return path
        }
        return Array(Set(paths))
    }
}
