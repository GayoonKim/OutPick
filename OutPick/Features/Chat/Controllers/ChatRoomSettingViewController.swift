//
//  ChatRoomSettingViewController.swift
//  OutPick
//
//  Created by 김가윤 on 8/5/24.
//

import UIKit
import Combine
import FirebaseFirestore

enum ChatRoomSettingEvent {
    case roomUpdated(ChatRoom)
    case roomExited(roomID: String)
    case requestEditRoom(ChatRoom)
    case requestShowUserProfile(LocalChatUser)
    case requestShowBannedUsers
}

class ChatRoomSettingViewController: UICollectionViewController, UIGestureRecognizerDelegate, UINavigationControllerDelegate/*, ChatModalAnimatable*/ {
    private lazy var floatingLeaveButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "rectangle.portrait.and.arrow.right")
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        let b = UIButton(configuration: config)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.tintColor = OutPickTheme.ColorToken.destructive
        b.backgroundColor = OutPickTheme.ColorToken.surfaceBase
        b.layer.cornerRadius = 12
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
        b.tintColor = OutPickTheme.ColorToken.accent
        b.backgroundColor = OutPickTheme.ColorToken.surfaceBase
        b.layer.cornerRadius = 12
        b.accessibilityLabel = "알림"
        b.addTarget(self, action: #selector(didTapFloatingNotice), for: .touchUpInside)
        return b
    }()

    private lazy var floatingBanButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "person.crop.circle.badge.xmark")
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = OutPickTheme.ColorToken.destructive
        button.backgroundColor = OutPickTheme.ColorToken.surfaceBase
        button.layer.cornerRadius = 12
        button.accessibilityLabel = "차단 사용자"
        button.addTarget(self, action: #selector(didTapFloatingBan), for: .touchUpInside)
        return button
    }()

    var interactiveTransition: UIPercentDrivenInteractiveTransition?
    
    private let viewModel: ChatRoomSettingViewModel
    private let attachmentImageLoader: ChatAttachmentImageLoading
    private let videoResolver: ChatVideoPlaybackResolving
    private let photoLibrarySaver: PhotoLibrarySaving
    private let roomImageManager: RoomImageManaging
    private let avatarImageManager: AvatarImageManaging
    private let currentUserProvider: any CurrentUserProviding
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
        case participantsItem([ChatRoomParticipant])
    }
    
    typealias DataSourceType = UICollectionViewDiffableDataSource<Section, Item>
    var dataSource: DataSourceType!
    
    private var cancellables = Set<AnyCancellable>()

    private var roomInfo: ChatRoom { viewModel.roomInfo }
    private var mediaItems: [ChatRoomSettingMediaItem] { viewModel.mediaItems }
    private var participants: [ChatRoomParticipant] { viewModel.participants }
    
    var onEvent: (ChatRoomSettingEvent) -> Void = { _ in }

    var onRequestOpenGallery: ((UIViewController) -> Void)?
    
    init(
        viewModel: ChatRoomSettingViewModel,
        attachmentImageLoader: ChatAttachmentImageLoading,
        videoResolver: ChatVideoPlaybackResolving,
        photoLibrarySaver: PhotoLibrarySaving,
        roomImageManager: RoomImageManaging,
        avatarImageManager: AvatarImageManaging,
        currentUserProvider: any CurrentUserProviding
    ) {
        self.viewModel = viewModel
        self.attachmentImageLoader = attachmentImageLoader
        self.videoResolver = videoResolver
        self.photoLibrarySaver = photoLibrarySaver
        self.roomImageManager = roomImageManager
        self.avatarImageManager = avatarImageManager
        self.currentUserProvider = currentUserProvider
        let layout = Self.configureLayout(
            viewModel.roomInfo,
            participantCount: viewModel.participants.count,
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
        
        self.view.backgroundColor = OutPickTheme.ColorToken.backgroundBase
        
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
        view.addSubview(floatingBanButton)
        floatingBanButton.isHidden = !viewModel.isRoleManagementEnabled

        NSLayoutConstraint.activate([
            floatingLeaveButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            floatingLeaveButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -12),
            floatingLeaveButton.heightAnchor.constraint(equalToConstant: 44),

            floatingNoticeButton.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            floatingNoticeButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -12),
            floatingNoticeButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        NSLayoutConstraint.activate([
            floatingBanButton.leadingAnchor.constraint(equalTo: floatingLeaveButton.trailingAnchor, constant: 8),
            floatingBanButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -12),
            floatingBanButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        updateInsetsForBottomButtons()
    }

    @objc private func didTapFloatingLeave() {
        leaveRoomTapped()
    }

    @objc private func didTapFloatingNotice() {
        noticeTapped()
    }

    @objc private func didTapFloatingBan() {
        onEvent(.requestShowBannedUsers)
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

    private static func configureLayout(_ room: ChatRoom, participantCount: Int, mediaCount: Int) -> UICollectionViewCompositionalLayout {
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
                let estimatedHeight = max(100, 40 + participantCount * 60)
                let itemSize = NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .estimated(CGFloat(estimatedHeight))
                )
                let item = NSCollectionLayoutItem(layoutSize: itemSize)

                let groupSize = NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .estimated(CGFloat(estimatedHeight))
                )
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

        viewModel.$participants
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] users in
                self?.updateParticipantsSection(with: users)
            }
            .store(in: &cancellables)

        viewModel.$roleState
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                if !state.isManagementEnabled,
                   let alert = self.presentedViewController as? UIAlertController,
                   alert.preferredStyle == .actionSheet {
                    alert.dismiss(animated: true)
                }
                if !state.isManagementEnabled,
                   self.presentedViewController is OwnershipTransferSelectionViewController {
                    self.dismiss(animated: true)
                }
                let canManageBans = state.role == .owner || state.role == .moderator
                self.floatingBanButton.isHidden = !(canManageBans && state.isManagementEnabled)
                self.updateParticipantsSection(with: self.participants)
            }
            .store(in: &cancellables)
    }
    
    private func configureDataSource() -> DataSourceType {
        dataSource = DataSourceType(collectionView: collectionView) { (collectionView, indexPath, item) -> UICollectionViewCell? in
            switch item {
            case .roomInfoItem(_):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ChatRoomInfoCell.reuseIdentifier, for: indexPath) as! ChatRoomInfoCell
                cell.configureCell(
                    room: self.roomInfo,
                    roomImageManager: self.roomImageManager,
                    currentUserUID: self.currentUserProvider.canonicalUserID
                )
                
                cell.editButtonTapped = { [weak self] in
                    guard let self = self else { return }
                    self.onEvent(.requestEditRoom(self.roomInfo))
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
                
            case let .participantsItem(participants):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ParticipantsSectionParticipantCell.reuseIdentifier, for: indexPath) as! ParticipantsSectionParticipantCell
                cell.configureCell(
                    participants,
                    currentUserID: self.currentUserProvider.canonicalUserID,
                    avatarImageManager: self.avatarImageManager
                )
                cell.onSelectParticipant = { [weak self] participant in
                    self?.handleParticipantSelection(participant)
                }
                self.configureParticipantModeration(on: cell)

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
            let vc = MediaGalleryViewController(
                items: items,
                photoLibrarySaver: self.photoLibrarySaver,
                videoResolver: self.videoResolver
            )
            let attachmentImageLoader = self.attachmentImageLoader
            vc.cachedImageProvider = { path in
                await attachmentImageLoader.cachedImage(for: path)
            }
            vc.loadImageProvider = { path, maxBytes in
                try? await attachmentImageLoader.loadImage(for: path, maxBytes: maxBytes)
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
        snapshot.appendItems([.participantsItem(self.participants)], toSection: .participantsSection)
        
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    @MainActor
    func applyEditedRoom(_ updatedRoom: ChatRoom) async {
        let nextKey = updatedRoom.coverImagePath
        lastRoomCoverKey = nextKey
        viewModel.updateRoomInfo(updatedRoom)
        onEvent(.roomUpdated(updatedRoom))
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
                    cell.configureCell(
                        room: self.roomInfo,
                        roomImageManager: self.roomImageManager,
                        currentUserUID: self.currentUserProvider.canonicalUserID
                    )
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
            
            self.collectionView.setCollectionViewLayout(Self.configureLayout(self.roomInfo, participantCount: self.participants.count, mediaCount: self.mediaItems.count), animated: false)
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
    private func updateParticipantsSection(with participants: [ChatRoomParticipant]) {
        var snapshot = dataSource.snapshot()
        snapshot.deleteItems(snapshot.itemIdentifiers(inSection: .participantsSection))
        snapshot.appendItems([.participantsItem(participants)], toSection: .participantsSection)
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self = self else { return }
            self.collectionView.setCollectionViewLayout(Self.configureLayout(self.roomInfo, participantCount: participants.count, mediaCount: self.mediaItems.count), animated: false)
            if let indexPath = self.dataSource.indexPath(for: .participantsItem(participants)),
               let cell = self.collectionView.cellForItem(at: indexPath) as? ParticipantsSectionParticipantCell {
                cell.configureCell(
                    participants,
                    currentUserID: self.currentUserProvider.canonicalUserID,
                    avatarImageManager: self.avatarImageManager
                )
                cell.onSelectParticipant = { [weak self] participant in
                    self?.handleParticipantSelection(participant)
                }
                self.configureParticipantModeration(on: cell)
            }
        }
    }

    private func handleParticipantSelection(_ participant: ChatRoomParticipant) {
        onEvent(.requestShowUserProfile(participant.user))
    }


    private func configureParticipantModeration(on cell: ParticipantsSectionParticipantCell) {
        cell.canModerateParticipant = { [weak self] participant in
            self?.viewModel.actions(for: participant).isEmpty == false
        }
        cell.onModerateParticipant = { [weak self] participant in
            self?.presentParticipantActions(for: participant)
        }
    }

    private func presentParticipantActions(for participant: ChatRoomParticipant) {
        let actions = viewModel.actions(for: participant)
        guard !actions.isEmpty else { return }
        let sheet = UIAlertController(
            title: participant.user.nickname,
            message: nil,
            preferredStyle: .actionSheet
        )
        for action in actions {
            switch action {
            case .assignModerator:
                sheet.addAction(UIAlertAction(title: "관리자로 지정", style: .default) { [weak self] _ in
                    self?.confirmRoleChange(
                        message: "\(participant.user.nickname)님을 관리자로 지정할까요?"
                    ) { [weak self] in
                        try await self?.viewModel.assignModerator(participant)
                    }
                })
            case .revokeModerator:
                sheet.addAction(UIAlertAction(title: "관리자 권한 해제", style: .destructive) { [weak self] _ in
                    self?.confirmRoleChange(
                        message: "\(participant.user.nickname)님의 관리자 권한을 해제할까요?"
                    ) { [weak self] in
                        try await self?.viewModel.revokeModerator(participant)
                    }
                })
            case .resignModerator:
                sheet.addAction(UIAlertAction(title: "관리자 그만두기", style: .destructive) { [weak self] _ in
                    self?.confirmRoleChange(message: "관리자 권한을 내려놓을까요?") { [weak self] in
                        try await self?.viewModel.resignModerator()
                    }
                })
            case .removeFromRoom:
                sheet.addAction(UIAlertAction(title: "방에서 내보내기", style: .destructive) { [weak self] _ in
                    self?.presentRemovalReasons(for: participant.user)
                })
            }
        }
        sheet.addAction(UIAlertAction(title: "취소", style: .cancel))
        present(sheet, animated: true)
    }

    private func confirmRoleChange(
        message: String,
        operation: @escaping @MainActor () async throws -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        alert.addAction(UIAlertAction(title: "확인", style: .default) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await operation()
                } catch {
                    await self.viewModel.reconcileParticipantsAfterRoleEvent()
                    self.presentModerationFailureAlert(error)
                }
            }
        })
        present(alert, animated: true)
    }

    private func presentRemovalReasons(for user: LocalChatUser) {
        let sheet = UIAlertController(
            title: "내보내기 사유",
            message: "이 사용자는 해제하기 전까지 다시 참여할 수 없어요.",
            preferredStyle: .actionSheet
        )
        for reason in ChatRoomMemberRemovalReason.allCases {
            sheet.addAction(UIAlertAction(title: reason.title, style: .destructive) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        try await viewModel.removeParticipant(user, reasonCode: reason.rawValue)
                    } catch {
                        presentModerationFailureAlert(error)
                    }
                }
            })
        }
        sheet.addAction(UIAlertAction(title: "취소", style: .cancel))
        present(sheet, animated: true)
    }

    private func presentModerationFailureAlert(_ error: Error) {
        let alert = UIAlertController(
            title: "처리하지 못했어요",
            message: ChatRoomRoleMutationErrorMessage.message(for: error),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "확인", style: .default))
        present(alert, animated: true)
    }

    @MainActor
    func handleRoomRoleEvent() {
        Task { @MainActor [weak self] in
            await self?.viewModel.reconcileParticipantsAfterRoleEvent()
        }
    }
    
    private func leaveRoomTapped() {
        guard viewModel.roleState.source == .server || viewModel.roleState.source == .mutation,
              viewModel.roleState.isObserving else {
            presentRoleUnavailableAlert()
            return
        }
        if viewModel.roleState.role == .owner {
            presentOwnershipTransferFlow()
            return
        }
        ConfirmView.presentLeave(in: self.view,
                                 isOwner: false) { [weak self] in
            guard let self = self else { return }
            Task {
                do {
                    let result = try await self.viewModel.leaveOrCloseRoom()
                    await MainActor.run {
                        self.onEvent(.roomExited(roomID: result.roomID))
                    }
                } catch {
                    await MainActor.run {
                        self.presentLeaveFailureAlert(error)
                    }
                }
            }
        }
    }

    private func presentOwnershipTransferFlow() {
        let moderators = viewModel.eligibleOwnershipSuccessors
        guard !moderators.isEmpty else {
            let alert = UIAlertController(
                title: "방을 종료할까요?",
                message: "방장 권한을 넘길 관리자가 없어요\n나가면 방이 종료돼요",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "취소", style: .cancel))
            alert.addAction(UIAlertAction(title: "방 종료", style: .destructive) { [weak self] _ in
                self?.performRoomExit { [weak self] in
                    try await self?.viewModel.leaveOrCloseRoom()
                }
            })
            present(alert, animated: true)
            return
        }

        let selectionViewController = OwnershipTransferSelectionViewController(
            candidates: moderators,
            avatarImageManager: avatarImageManager
        )
        selectionViewController.onConfirm = { [weak self, weak selectionViewController] participant in
            selectionViewController?.dismiss(animated: true) { [weak self] in
                self?.confirmOwnershipTransfer(to: participant)
            }
        }
        selectionViewController.modalPresentationStyle = .pageSheet
        if let sheet = selectionViewController.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.selectedDetentIdentifier = .large
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 24
        }
        present(selectionViewController, animated: true)
    }

    private func confirmOwnershipTransfer(to participant: ChatRoomParticipant) {
        let nickname = participant.user.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = nickname.isEmpty ? "선택한 관리자" : "\(nickname)님"
        let alert = UIAlertController(
            title: "방장 권한을 넘길까요?",
            message: "\(displayName)에게 방장 권한을 넘긴 뒤 채팅방에서 나가요\n권한을 넘기면 되돌릴 수 없어요",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        alert.addAction(UIAlertAction(title: "넘기고 나가기", style: .destructive) { [weak self] _ in
            self?.performRoomExit { [weak self] in
                try await self?.viewModel.transferOwnershipAndLeave(to: participant)
            }
        })
        present(alert, animated: true)
    }

    private func performRoomExit(
        operation: @escaping @MainActor () async throws -> ChatRoomExitResult?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                guard let result = try await operation() else { return }
                self.onEvent(.roomExited(roomID: result.roomID))
            } catch {
                await self.viewModel.reconcileParticipantsAfterRoleEvent()
                self.presentLeaveFailureAlert(error)
            }
        }
    }

    private func presentRoleUnavailableAlert() {
        let alert = UIAlertController(
            title: "연결을 확인해 주세요",
            message: "최신 방 권한을 확인한 뒤 다시 시도해 주세요.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "확인", style: .default))
        present(alert, animated: true)
    }

    private func presentLeaveFailureAlert(_ error: Error) {
        print("❌ leave-or-close failed:", error)
        let alert = UIAlertController(
            title: "나가기에 실패했어요",
            message: ChatRoomRoleMutationErrorMessage.message(for: error),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "확인", style: .default))
        present(alert, animated: true)
    }

    private func noticeTapped() {
        print("🔔 알림 버튼 탭됨")
        // TODO: 알림 설정 화면/토글 연결
    }

    private func configureCollectionView() {
        collectionView.backgroundColor = OutPickTheme.ColorToken.backgroundBase
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

private final class OwnershipTransferSelectionViewController: UIViewController {
    private let candidates: [ChatRoomParticipant]
    private let avatarImageManager: AvatarImageManaging
    private var selectedParticipant: ChatRoomParticipant?
    private var candidateRows: [OwnershipSuccessorRow] = []

    var onConfirm: ((ChatRoomParticipant) -> Void)?

    private lazy var eyebrowLabel: UILabel = {
        let label = UILabel()
        label.text = "ROOM OWNERSHIP"
        label.font = Self.scaledMonospacedFont(size: 11, weight: .semibold, textStyle: .caption1)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = OutPickTheme.ColorToken.accent
        return label
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = "새 방장 선택"
        label.font = Self.editorialFont(size: 34, weight: .bold, textStyle: .largeTitle)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = OutPickTheme.ColorToken.textPrimary
        label.numberOfLines = 0
        return label
    }()

    private lazy var descriptionLabel: UILabel = {
        let label = UILabel()
        label.text = "방을 이어서 운영할 관리자를 선택해 주세요"
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = OutPickTheme.ColorToken.textSecondary
        label.numberOfLines = 0
        return label
    }()

    private lazy var accentLine: UIView = {
        let view = UIView()
        view.backgroundColor = OutPickTheme.ColorToken.accent
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var listCaptionLabel: UILabel = {
        let label = UILabel()
        label.text = "01  APPOINTED MODERATORS"
        label.font = Self.scaledMonospacedFont(size: 10, weight: .bold, textStyle: .caption2)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = OutPickTheme.ColorToken.textSecondary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "xmark"), for: .normal)
        button.tintColor = OutPickTheme.ColorToken.iconSecondary
        button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var candidateStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var footerDivider: UIView = {
        let view = UIView()
        view.backgroundColor = OutPickTheme.ColorToken.borderSubtle
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var footerStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [confirmButton])
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    private lazy var confirmButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "넘기기"
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            let baseFont = UIFont.systemFont(ofSize: 16, weight: .bold)
            attributes.font = UIFontMetrics(forTextStyle: .headline).scaledFont(for: baseFont)
            return attributes
        }
        let button = UIButton(configuration: configuration)
        button.isEnabled = false
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)
        button.configurationUpdateHandler = { button in
            button.configuration?.baseBackgroundColor = button.isEnabled
                ? OutPickTheme.ColorToken.accent
                : OutPickTheme.ColorToken.surfacePressed
            button.configuration?.baseForegroundColor = button.isEnabled
                ? OutPickTheme.ColorToken.backgroundBase
                : OutPickTheme.ColorToken.textDisabled
        }
        return button
    }()

    init(candidates: [ChatRoomParticipant], avatarImageManager: AvatarImageManaging) {
        self.candidates = candidates
        self.avatarImageManager = avatarImageManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = OutPickTheme.ColorToken.backgroundBase
        configureLayout()
        configureCandidates()
    }

    private func configureLayout() {
        let headerStack = UIStackView(arrangedSubviews: [eyebrowLabel, titleLabel, descriptionLabel, accentLine])
        headerStack.axis = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 8
        headerStack.setCustomSpacing(12, after: titleLabel)
        headerStack.setCustomSpacing(20, after: descriptionLabel)
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(headerStack)
        view.addSubview(closeButton)
        view.addSubview(listCaptionLabel)
        view.addSubview(scrollView)
        view.addSubview(footerDivider)
        view.addSubview(footerStack)
        scrollView.addSubview(candidateStack)

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            headerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            headerStack.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -12),

            accentLine.widthAnchor.constraint(equalToConstant: 44),
            accentLine.heightAnchor.constraint(equalToConstant: 2),

            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            listCaptionLabel.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 28),
            listCaptionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            listCaptionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            scrollView.topAnchor.constraint(equalTo: listCaptionLabel.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footerDivider.topAnchor),

            candidateStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            candidateStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            candidateStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            candidateStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            candidateStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),

            footerDivider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footerDivider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footerDivider.bottomAnchor.constraint(equalTo: footerStack.topAnchor, constant: -14),
            footerDivider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

            footerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            footerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            footerStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            confirmButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 52)
        ])
    }

    private func configureCandidates() {
        candidateRows = candidates.enumerated().map { index, participant in
            let row = OwnershipSuccessorRow(
                participant: participant,
                ordinal: index + 1,
                avatarImageManager: avatarImageManager
            )
            row.addTarget(self, action: #selector(candidateTapped(_:)), for: .touchUpInside)
            candidateStack.addArrangedSubview(row)
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 68).isActive = true
            return row
        }
    }

    @objc private func candidateTapped(_ sender: OwnershipSuccessorRow) {
        selectedParticipant = sender.participant
        for row in candidateRows {
            row.isSelected = row.participant.userID == sender.participant.userID
        }
        confirmButton.isEnabled = true
    }

    @objc private func confirmTapped() {
        guard let selectedParticipant else { return }
        confirmButton.isEnabled = false
        onConfirm?(selectedParticipant)
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private static func editorialFont(
        size: CGFloat,
        weight: UIFont.Weight,
        textStyle: UIFont.TextStyle
    ) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let serif = base.fontDescriptor.withDesign(.serif).map {
            UIFont(descriptor: $0, size: size)
        } ?? base
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: serif)
    }

    private static func scaledMonospacedFont(
        size: CGFloat,
        weight: UIFont.Weight,
        textStyle: UIFont.TextStyle
    ) -> UIFont {
        UIFontMetrics(forTextStyle: textStyle).scaledFont(
            for: .monospacedSystemFont(ofSize: size, weight: weight)
        )
    }
}

private final class OwnershipSuccessorRow: UIControl {
    let participant: ChatRoomParticipant
    private let ordinal: Int
    private let avatarImageManager: AvatarImageManaging
    private var avatarLoadTask: Task<Void, Never>?

    private lazy var ordinalLabel: UILabel = {
        let label = UILabel()
        label.text = String(format: "%02d", ordinal)
        label.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(
            for: .monospacedSystemFont(ofSize: 10, weight: .bold)
        )
        label.adjustsFontForContentSizeCategory = true
        label.textColor = OutPickTheme.ColorToken.accent
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var selectionRail: UIView = {
        let view = UIView()
        view.backgroundColor = OutPickTheme.ColorToken.accent
        view.layer.cornerRadius = 1.5
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var avatarImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "Default_Profile"))
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 10
        imageView.backgroundColor = OutPickTheme.ColorToken.surfaceElevated
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var nicknameLabel: UILabel = {
        let label = UILabel()
        let nickname = participant.user.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        label.text = nickname.isEmpty ? "알 수 없는 사용자" : nickname
        let base = UIFont.systemFont(ofSize: 21, weight: .semibold)
        let serif = base.fontDescriptor.withDesign(.serif).map {
            UIFont(descriptor: $0, size: 21)
        } ?? base
        label.font = UIFontMetrics(forTextStyle: .title3).scaledFont(for: serif)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = OutPickTheme.ColorToken.textPrimary
        label.numberOfLines = 0
        return label
    }()

    private lazy var checkmarkImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "circle"))
        imageView.tintColor = OutPickTheme.ColorToken.iconSecondary
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    override var isSelected: Bool {
        didSet { applySelectionStyle() }
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.12) {
                self.alpha = self.isHighlighted ? 0.62 : 1
                self.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.99, y: 0.99)
                    : .identity
            }
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isHidden == false,
              alpha > 0.01,
              isUserInteractionEnabled,
              self.point(inside: point, with: event) else {
            return nil
        }
        return self
    }

    init(
        participant: ChatRoomParticipant,
        ordinal: Int,
        avatarImageManager: AvatarImageManaging
    ) {
        self.participant = participant
        self.ordinal = ordinal
        self.avatarImageManager = avatarImageManager
        super.init(frame: .zero)
        configureLayout()
        loadAvatarIfNeeded()
        applySelectionStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        avatarLoadTask?.cancel()
    }

    private func configureLayout() {
        layer.cornerRadius = 16
        layer.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false

        let labelsStack = UIStackView(arrangedSubviews: [nicknameLabel])
        labelsStack.axis = .vertical
        labelsStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(selectionRail)
        addSubview(ordinalLabel)
        addSubview(avatarImageView)
        addSubview(labelsStack)
        addSubview(checkmarkImageView)

        NSLayoutConstraint.activate([
            selectionRail.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            selectionRail.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            selectionRail.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            selectionRail.widthAnchor.constraint(equalToConstant: 3),

            ordinalLabel.leadingAnchor.constraint(equalTo: selectionRail.trailingAnchor, constant: 10),
            ordinalLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            ordinalLabel.widthAnchor.constraint(equalToConstant: 22),

            avatarImageView.leadingAnchor.constraint(equalTo: ordinalLabel.trailingAnchor, constant: 10),
            avatarImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: 52),
            avatarImageView.heightAnchor.constraint(equalToConstant: 52),

            labelsStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 10),
            labelsStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10),
            labelsStack.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 14),
            labelsStack.trailingAnchor.constraint(lessThanOrEqualTo: checkmarkImageView.leadingAnchor, constant: -12),
            labelsStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            checkmarkImageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            checkmarkImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkmarkImageView.widthAnchor.constraint(equalToConstant: 24),
            checkmarkImageView.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    private func applySelectionStyle() {
        backgroundColor = isSelected
            ? OutPickTheme.ColorToken.surfaceBase
            : .clear
        layer.borderColor = (isSelected
            ? OutPickTheme.ColorToken.accent
            : OutPickTheme.ColorToken.borderSubtle).cgColor
        checkmarkImageView.image = UIImage(systemName: isSelected ? "checkmark.circle.fill" : "circle")
        checkmarkImageView.tintColor = isSelected
            ? OutPickTheme.ColorToken.accent
            : OutPickTheme.ColorToken.iconSecondary
        selectionRail.isHidden = !isSelected
    }

    private func loadAvatarIfNeeded() {
        guard let path = participant.user.profileImagePath, !path.isEmpty else { return }
        avatarLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if let cached = await avatarImageManager.cachedAvatar(for: path) {
                guard !Task.isCancelled else { return }
                avatarImageView.image = cached
                return
            }
            if let image = try? await avatarImageManager.loadAvatar(for: path, maxBytes: 3 * 1024 * 1024),
               !Task.isCancelled {
                avatarImageView.image = image
            }
        }
    }
}
