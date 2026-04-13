//
//  ChatRoomSettingViewController.swift
//  OutPick
//
//  Created by 김가윤 on 8/5/24.
//

import UIKit
import Combine
import GRDB
import FirebaseFirestore


class ChatRoomSettingViewController: UICollectionViewController, UIGestureRecognizerDelegate, UINavigationControllerDelegate/*, ChatModalAnimatable*/ {
    private lazy var floatingLeaveButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "rectangle.portrait.and.arrow.right")
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        let b = UIButton(configuration: config)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.tintColor = .label // 아이콘만, 배경 없이
        b.accessibilityLabel = "나가기"
        b.addTarget(self, action: #selector(didTapFloatingLeave), for: .touchUpInside)
        return b
    }()

    private lazy var floatingNoticeButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "bell")
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        let b = UIButton(configuration: config)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.tintColor = .label // 아이콘만, 배경 없이
        b.accessibilityLabel = "알림"
        b.addTarget(self, action: #selector(didTapFloatingNotice), for: .touchUpInside)
        return b
    }()
    
    var interactiveTransition: UIPercentDrivenInteractiveTransition?
    
    private let viewModel: ChatRoomSettingViewModel
    private let mediaManager: ChatMediaManaging
    private let roomImageManager: RoomImageManaging
    private let avatarImageManager: ChatAvatarImageManaging
    private var lastRoomCoverKey: String? = nil
    private var coverPrefetchTask: Task<Void, Never>? = nil
    /// 끝 근처에서 선로딩을 트리거할 임계값(px)
    private let participantsBottomPrefetchThreshold: CGFloat = 600
    
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
        case mediaItem
        case participantsItem([LocalUser])
    }
    
    typealias DataSourceType = UICollectionViewDiffableDataSource<Section, Item>
    var dataSource: DataSourceType!
    
    private var cancellables = Set<AnyCancellable>()

    private var roomInfo: ChatRoom { viewModel.roomInfo }
    private var mediaItems: [ChatRoomSettingMediaItem] { viewModel.mediaItems }
    private var localUsers: [LocalUser] { viewModel.localUsers }
    
    
    var onRoomUpdated: ((ChatRoom) -> Void)?
    var onRequestEditRoom: ((ChatRoom) -> Void)?
    var onLeaveCompleted: ((String) -> Void)?
    var onRequestShowUserProfile: ((LocalUser) -> Void)?

    var onRequestOpenGallery: ((UIViewController) -> Void)?
    
    init(
        viewModel: ChatRoomSettingViewModel,
        mediaManager: ChatMediaManaging,
        roomImageManager: RoomImageManaging,
        avatarImageManager: ChatAvatarImageManaging
    ) {
        self.viewModel = viewModel
        self.mediaManager = mediaManager
        self.roomImageManager = roomImageManager
        self.avatarImageManager = avatarImageManager
        let layout = Self.configureLayout(
            viewModel.roomInfo,
            localUsers: viewModel.localUsers,
            mediaCount: viewModel.mediaItems.count
        )
        super.init(collectionViewLayout: layout)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        print("💧 ChatRoomSettingViewController deinit")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.backgroundColor = .secondarySystemBackground
        
        configureCollectionView()
        bindViewModel()
        applyInitialSnapshot()
        configureBottomButtons()
        updateRoomInfoSection()

        Task { @MainActor [weak self] in
            guard let self else { return }
            async let mediaLoad: Void = self.viewModel.loadInitialMedia()
            async let participantsLoad: Void = self.viewModel.loadInitialParticipants()
            _ = await (mediaLoad, participantsLoad)
        }
    }
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateInsetsForBottomButtons()
    }
    private func configureBottomButtons() {
        let guide = view.safeAreaLayoutGuide
        view.addSubview(floatingLeaveButton)
        view.addSubview(floatingNoticeButton)

        NSLayoutConstraint.activate([
            floatingLeaveButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            floatingLeaveButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -12),
            floatingLeaveButton.heightAnchor.constraint(equalToConstant: 44),

            floatingNoticeButton.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            floatingNoticeButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -12),
            floatingNoticeButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        updateInsetsForBottomButtons()
    }

    @objc private func didTapFloatingLeave() {
        leaveRoomTapped()
    }

    @objc private func didTapFloatingNotice() {
        noticeTapped()
    }

    private func updateInsetsForBottomButtons() {
        let buttonHeight: CGFloat = 44
        let verticalMargin: CGFloat = 12
        let safeBottom = view.safeAreaInsets.bottom
        let neededBottom = buttonHeight + verticalMargin * 2 + safeBottom
        collectionView.contentInset.bottom = max(collectionView.contentInset.bottom, neededBottom)
        collectionView.verticalScrollIndicatorInsets.bottom = max(collectionView.verticalScrollIndicatorInsets.bottom, neededBottom)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        coverPrefetchTask?.cancel()
    }

    private static func configureLayout(_ room: ChatRoom, localUsers: [LocalUser], mediaCount: Int) -> UICollectionViewCompositionalLayout {
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
                let height: CGFloat = mediaCount > 0 ? 130 : 44
                
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(height))
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                
                let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(height))
                let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])
                
                let section = NSCollectionLayoutSection(group: group)
                section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 10, bottom: 10, trailing: 10)
                
                return section
                
            case .participantsSection:
                let count = localUsers.count
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
                section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 10, bottom: 16, trailing: 10)
                return section
            }
        }
    }

    private func bindViewModel() {
        viewModel.$roomInfo
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateRoomInfoSection()
            }
            .store(in: &cancellables)

        viewModel.$mediaItems
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateMediaSection()
            }
            .store(in: &cancellables)

        viewModel.$localUsers
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] users in
                self?.updateParticipantsSection(with: users)
            }
            .store(in: &cancellables)
    }
    
    private func configureDataSource() -> DataSourceType {
        dataSource = DataSourceType(collectionView: collectionView) { (collectionView, indexPath, item) -> UICollectionViewCell? in
            switch item {
            case .roomInfoItem(_):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ChatRoomInfoCell.reuseIdentifier, for: indexPath) as! ChatRoomInfoCell
                cell.configureCell(room: self.roomInfo, roomImageManager: self.roomImageManager)
                
                cell.editButtonTapped = { [weak self] in
                    guard let self = self else { return }
                    self.onRequestEditRoom?(self.roomInfo)
                }
                
                return cell
                
            case .mediaItem:
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ChatRoomMediaCollectionViewCell.reuseIdentifier, for: indexPath) as! ChatRoomMediaCollectionViewCell
                cell.configureCell(for: self.mediaItems) { [weak self] item in
                    guard let self else { return nil }
                    return await self.viewModel.thumbnailImage(for: item)
                }
                cell.onOpenGallery = { [weak self] in
                    guard let self = self else { return }
                    self.openGallery()
                }
                return cell
                
            case let .participantsItem(localUsers):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ParticipantsSectionParticipantCell.reuseIdentifier, for: indexPath) as! ParticipantsSectionParticipantCell
                cell.configureCell(localUsers, avatarImageManager: self.avatarImageManager)
                cell.onSelectParticipant = { [weak self] user in
                    self?.onRequestShowUserProfile?(user)
                }

                return cell
            }
        }
        return dataSource
    }
    
    private func pushOrPresent(_ vc: UIViewController) {
        vc.modalPresentationStyle = .fullScreen
        // 우선 부모가 있으면 부모가 모달 오픈 (child → parent 경유가 안전)
        if let host = self.parent {
            host.present(vc, animated: true)
            return
        }
        // 최후 폴백: 자기 자신에서 present
        self.present(vc, animated: true)
    }

    private func openGallery() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let items = await self.buildGalleryItems()
            guard !items.isEmpty else { return }
            print(#function, "items: \(items)")
            let vc = MediaGalleryViewController(items: items)
            let mediaManager = self.mediaManager
            vc.cachedImageProvider = { path in
                await mediaManager.cachedImage(for: path)
            }
            vc.loadImageProvider = { path, maxBytes in
                try? await mediaManager.loadImage(for: path, maxBytes: maxBytes)
            }
            vc.downloadURLResolver = { path in
                try await mediaManager.resolveURL(for: path)
            }
            vc.modalPresentationStyle = .fullScreen
            self.pushOrPresent(vc)
        }
    }

    /// ViewModel이 유지하는 현재 미디어 상태를 갤러리 아이템으로 변환
    private func buildGalleryItems() async -> [MediaGalleryViewController.GalleryItem] {
        let galleryItems = await viewModel.buildGalleryItems()
        return galleryItems.map { item in
            .init(
                id: item.id,
                image: item.image,
                isVideo: item.isVideo,
                sentAt: item.sentAt,
                thumbnailPath: item.thumbnailPath,
                originalPath: item.originalPath,
                videoPath: item.videoPath
            )
        }
    }
    
    private func applyInitialSnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        
        snapshot.appendSections(Section.allCases)
        snapshot.appendItems([.roomInfoItem(self.roomInfo)], toSection: .roomInfoSection)
        snapshot.appendItems([.mediaItem], toSection: .mediaSection)
        snapshot.appendItems([.participantsItem(self.localUsers)], toSection: .participantsSection)
        
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    @MainActor
    func applyEditedRoom(_ updatedRoom: ChatRoom) async {
        let nextKey = updatedRoom.coverImagePath
        lastRoomCoverKey = nextKey
        viewModel.updateRoomInfo(updatedRoom)
        onRoomUpdated?(updatedRoom)
    }
    
    private func updateRoomInfoSection() {
        let key = self.roomInfo.coverImagePath

        // 내부 헬퍼: 단일 아이템만 경량 갱신
        func reloadRoomInfoItem() {
            guard let dataSource = self.dataSource else { return }
            var snapshot = dataSource.snapshot()
            let item: Item = .roomInfoItem(self.roomInfo)
            if snapshot.indexOfItem(item) != nil {
                snapshot.reloadItems([item])
            } else {
                snapshot.appendItems([item], toSection: .roomInfoSection)
            }
            dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
                guard let self = self else { return }
                if let indexPath = self.dataSource.indexPath(for: .roomInfoItem(self.roomInfo)),
                   let cell = self.collectionView.cellForItem(at: indexPath) as? ChatRoomInfoCell {
                    cell.configureCell(room: self.roomInfo, roomImageManager: self.roomImageManager)
                }
            }
        }

        // 2) 이미지가 없으면: 그냥 경량 reload
        guard let key, !key.isEmpty else {
            self.lastRoomCoverKey = nil
            reloadRoomInfoItem()
            return
        }

        // 3) 캐시 확인 후 필요 시 파이프라인으로 워밍
        coverPrefetchTask?.cancel()
        coverPrefetchTask = Task { [weak self] in
            guard let self = self else { return }
            let isCached = await self.roomImageManager.cachedImage(for: key) != nil
            if !isCached {
                do {
                    _ = try await self.roomImageManager.loadImage(for: key, maxBytes: 3 * 1024 * 1024)
                } catch {
                    print("[RoomInfo] cover prefetch failed: \(error)")
                }
            }
            guard !Task.isCancelled else { return }
            self.lastRoomCoverKey = key
            await MainActor.run {
                reloadRoomInfoItem()
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
        snapshot.appendItems([.mediaItem], toSection: .mediaSection)
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self = self else { return }
            
            self.collectionView.setCollectionViewLayout(Self.configureLayout(self.roomInfo, localUsers: self.localUsers, mediaCount: self.mediaItems.count), animated: false)
            if let indexPath = self.dataSource.indexPath(for: .mediaItem),
               let cell = self.collectionView.cellForItem(at: indexPath) as? ChatRoomMediaCollectionViewCell {
                cell.configureCell(for: self.mediaItems) { [weak self] item in
                    guard let self else { return nil }
                    return await self.viewModel.thumbnailImage(for: item)
                }
            }
        }
    }
    
    @MainActor
    private func updateParticipantsSection(with localUsers: [LocalUser]) {
        var snapshot = dataSource.snapshot()
        snapshot.deleteItems(snapshot.itemIdentifiers(inSection: .participantsSection))
        snapshot.appendItems([.participantsItem(localUsers)], toSection: .participantsSection)
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self = self else { return }
            self.collectionView.setCollectionViewLayout(Self.configureLayout(self.roomInfo, localUsers: localUsers, mediaCount: self.mediaItems.count), animated: false)
            if let indexPath = self.dataSource.indexPath(for: .participantsItem(localUsers)),
               let cell = self.collectionView.cellForItem(at: indexPath) as? ParticipantsSectionParticipantCell {
                cell.configureCell(localUsers, avatarImageManager: self.avatarImageManager)
                cell.onSelectParticipant = { [weak self] user in
                    self?.onRequestShowUserProfile?(user)
                }
            }
        }
    }
    
    private func leaveRoomTapped() {
        print("🚪 나가기 버튼 탭됨")
        // TODO: 실제 방 나가기 로직 연결 (확인 다이얼로그 → 서버/로컬 상태 정리)
        ConfirmView.presentLeave(in: self.view,
                                 isOwner: roomInfo.creatorID == LoginManager.shared.getUserEmail) { [weak self] in
            guard let self = self else { return }
            Task {
                guard let roomID = self.roomInfo.ID, !roomID.isEmpty else { return }

                SocketIOManager.shared.requestLeaveOrCloseRoom(roomID: roomID) { result in
                    switch result {
                    case .success:
                        Task {
                            do {
                                try GRDBManager.shared.deleteLocalRoomDataAndPruneUsers(roomID: roomID)
                            } catch {
                                print("❌ local cleanup failed:", error)
                            }

                            await MainActor.run {
                                if var profile = LoginManager.shared.currentUserProfile {
                                    profile.joinedRooms.removeAll { $0 == roomID }
                                    LoginManager.shared.setCurrentUserProfile(profile)
                                }
                                if let joinedRoomsStore = ChatDependencyContainer.joinedRoomsStore {
                                    joinedRoomsStore.remove(roomID)
                                }
                                SocketIOManager.shared.leaveRoom(roomID)
                                self.onLeaveCompleted?(roomID)
                            }
                        }

                    case .failure(let error):
                        // 서버 측 나가기/종료 실패 → 사용자에게 안내하고, 로컬은 그대로 두는게 안전
                        print("❌ leave-or-close failed:", error)
                        DispatchQueue.main.async { [weak self] in
                            guard let self else { return }
                            let alert = UIAlertController(
                                title: "나가기에 실패했어요",
                                message: error.localizedDescription,
                                preferredStyle: .alert
                            )
                            alert.addAction(UIAlertAction(title: "확인", style: .default))
                            self.present(alert, animated: true)
                        }
                    }
                }
            }
        }
    }

    private func noticeTapped() {
        print("🔔 알림 버튼 탭됨")
        // TODO: 알림 설정 화면/토글 연결
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

    // MARK: - Pagination Trigger via willDisplay (no scrollViewDidScroll)
    override func collectionView(_ collectionView: UICollectionView,
                                 willDisplay cell: UICollectionViewCell,
                                 forItemAt indexPath: IndexPath) {
        // 하단 근접 감지: 셀이 표시되기 직전에 한 번씩만 체크
        let distanceToBottom = collectionView.contentSize.height - collectionView.contentOffset.y - collectionView.bounds.height
        if viewModel.participantsHasMore && !viewModel.participantsIsLoading && distanceToBottom < participantsBottomPrefetchThreshold {
            Task { [weak self] in
                await self?.viewModel.loadMoreParticipantsIfNeeded()
            }
        }
        
        // 보수적으로: 참가자 섹션 셀(마지막 섹션)이 표시될 때도 한번 더 체크
        if let section = Section(rawValue: indexPath.section), section == .participantsSection {
            if viewModel.participantsHasMore && !viewModel.participantsIsLoading {
                Task { [weak self] in
                    await self?.viewModel.loadMoreParticipantsIfNeeded()
                }
            }
        }
        
        // 미디어 섹션 하단 근접 시 추가 로드
        if let section = Section(rawValue: indexPath.section), section == .mediaSection {
            if viewModel.mediaHasMore && !viewModel.mediaIsLoading {
                let distanceToBottom = collectionView.contentSize.height
                                     - collectionView.contentOffset.y
                                     - collectionView.bounds.height
                if distanceToBottom < participantsBottomPrefetchThreshold {
                    Task { [weak self] in
                        await self?.viewModel.loadMoreMediaIfNeeded()
                    }
                }
            }
        }
    }
}
