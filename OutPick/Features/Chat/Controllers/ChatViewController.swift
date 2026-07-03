//
//  ChatViewController.swift
//  OutPick
//
//  Created by 김가윤 on 10/14/24.
//

import Foundation
import UIKit
import Combine
import PhotosUI
import Firebase
import FirebaseStorage
import CryptoKit
import FirebaseFirestore

protocol ChatMessageCellDelegate: AnyObject {
    func cellDidLongPress(_ cell: ChatMessageCell)
}

class ChatViewController: UIViewController, UINavigationControllerDelegate, ChatModalAnimatable {
    typealias Item = ChatMessageListItem
    typealias MessageUpdateType = ChatMessageWindowUpdateType

    // Paging buffer size for scroll triggers
    private var pagingBuffer = 200
    
    var sideMenuBtn: UIBarButtonItem?
    private var joinRoomBtn: UIButton = UIButton(type: .system)
    
    var swipeRecognizer: UISwipeGestureRecognizer!
    
    private var chatMessageCollectionView = ChatMessageCollectionView()
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private var cancellables = Set<AnyCancellable>()
    private var initialLoadTask: Task<Void, Never>?
    private var realtimeSubscription: ChatRoomRealtimeSubscription?
    private var chatCustomMemucancellables = Set<AnyCancellable>()
    
    private var messageWindowStore = ChatMessageWindowStore()
    
    private var isUserInCurrentRoom = false
    
    private var replyMessage: ReplyPreview?
    private lazy var centeredStatusLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = OutPickTheme.ColorToken.textSecondary
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    private let chatRoomViewModel: ChatRoomViewModel
    
    private var avatarWarmupRoomID: String?
    
    enum Section: Hashable {
        case main
    }
    
    var room: ChatRoom?
    var roomID: String?
    var isRoomSaving: Bool = false
    
    var convertImagesTask: Task<Void, Error>? = nil
    var convertVideosTask: Task<Void, Error>? = nil
    private var searchJumpTask: Task<Void, Never>?

    typealias PendingImageUploadState = ChatPendingMediaUploadState
    private let pendingMediaUploadStore = ChatPendingMediaUploadStore()
    let mediaUploadUseCase: ChatMediaUploadUseCaseProtocol
    private let outgoingOutboxUseCase: ChatOutgoingOutboxUseCaseProtocol
    
    // MARK: - Managers (의존성 주입)
    private let attachmentImageLoader: ChatAttachmentImageLoading
    private let videoAssetLoader: ChatVideoAssetLoading
    private let storageURLResolver: ChatStorageURLResolving
    private let videoThumbnailGenerator: ChatVideoThumbnailGenerating
    let mediaProcessor: MediaProcessingServiceProtocol
    private let avatarImageManager: AvatarImageManaging
    private let profileSyncManager: ChatProfileSyncManaging
    weak var router: ChatRoomRouting?

    init(
        mediaUploadUseCase: ChatMediaUploadUseCaseProtocol,
        outgoingOutboxUseCase: ChatOutgoingOutboxUseCaseProtocol,
        attachmentImageLoader: ChatAttachmentImageLoading,
        videoAssetLoader: ChatVideoAssetLoading,
        storageURLResolver: ChatStorageURLResolving,
        videoThumbnailGenerator: ChatVideoThumbnailGenerating,
        mediaProcessor: MediaProcessingServiceProtocol,
        avatarImageManager: AvatarImageManaging,
        profileSyncManager: ChatProfileSyncManaging,
        viewModel: ChatRoomViewModel
    ) {
        self.mediaUploadUseCase = mediaUploadUseCase
        self.outgoingOutboxUseCase = outgoingOutboxUseCase
        self.attachmentImageLoader = attachmentImageLoader
        self.videoAssetLoader = videoAssetLoader
        self.storageURLResolver = storageURLResolver
        self.videoThumbnailGenerator = videoThumbnailGenerator
        self.mediaProcessor = mediaProcessor
        self.avatarImageManager = avatarImageManager
        self.profileSyncManager = profileSyncManager
        self.chatRoomViewModel = viewModel
        self.room = viewModel.room
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("Storyboard initialization is no longer supported for ChatViewController.")
    }

    static var currentRoomID: String? = nil
    
    // 중복 호출 방지를 위한 최근 트리거 인덱스
    private var minTriggerDistance: Int {
        chatRoomViewModel.minTriggerDistance
    }
    private static var lastTriggeredOlderIndex: Int?
    private static var lastTriggeredNewerIndex: Int?
    
    private var needsTransientBindingsRestore = false
    
    private var roomClosedSubscription: ChatRoomRuntimeSubscription?
    private var appLifecycleObservers: [NSObjectProtocol] = []
    
    deinit {
        let realtimeSubscription = realtimeSubscription
        Task { @MainActor in
            realtimeSubscription?.stop()
        }
        convertImagesTask?.cancel()
        convertVideosTask?.cancel()
        let chatRoomViewModel = chatRoomViewModel
        Task { @MainActor in
            chatRoomViewModel.cancelSearchWork()
        }
        imageViewerPrefetchTasks.forEach { $0.cancel() }
        imageViewerPrefetchTasks.removeAll()
        thumbnailPrefetchTasks.values.forEach { $0.cancel() }
        thumbnailPrefetchTasks.removeAll()
        videoPrefetchTasks.values.forEach { $0.cancel() }
        videoPrefetchTasks.removeAll()
        mediaPrefetchCleanupTask?.cancel()
        mediaPrefetchCleanupTask = nil
        let pendingMediaUploadStore = pendingMediaUploadStore
        Task { @MainActor in
            pendingMediaUploadStore.cancelAllTasks()
            pendingMediaUploadStore.removeAll()
        }
        appLifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
        appLifecycleObservers.removeAll()

        stopRoomClosedObservation()
    }
    
    private lazy var containerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    private lazy var attachmentView: AttachmentView = {
        let view = AttachmentView()
        view.translatesAutoresizingMaskIntoConstraints = false
        
        view.onButtonTapped = { [weak self] identifier in
            guard let self = self else { return }
            self.handleAttachmentButtonTap(identifier: identifier)
        }
        
        return view
    }()
    
    private lazy var chatUIView: ChatUIView = {
        let view = ChatUIView()
        view.isHidden = true
        
        view.onButtonTapped = { [weak self] identifier in
            guard let self = self else { return }
            self.handleAttachmentButtonTap(identifier: identifier)
        }
        
        return view
    }()
    
    private lazy var customNavigationBar: CustomNavigationBarView = {
        let navBar = CustomNavigationBarView()
        navBar.translatesAutoresizingMaskIntoConstraints = false
        
        return navBar
    }()
    
    private lazy var searchUI: ChatSearchUIView = {
        let view = ChatSearchUIView()
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        view.onPreviousTapped = { [weak self] in
            guard let self else { return }
            guard let index = self.chatRoomViewModel.moveToPreviousSearchResult() else { return }
            self.searchUI.updateSearchResult(self.makeSearchResultState())
            self.moveToMessageAndShake(index)
        }
        view.onNextTapped = { [weak self] in
            guard let self else { return }
            guard let index = self.chatRoomViewModel.moveToNextSearchResult() else { return }
            self.searchUI.updateSearchResult(self.makeSearchResultState())
            self.moveToMessageAndShake(index)
        }
        
        return view
    }()
    
    private lazy var chatCustomMenu: ChatCustomPopUpMenu = {
        let view = ChatCustomPopUpMenu()
        view.backgroundColor = OutPickTheme.ColorToken.backgroundRaised
        view.layer.borderColor = OutPickTheme.ColorToken.borderSubtle.cgColor
        view.layer.borderWidth = 1
        view.layer.cornerRadius = 20
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    private var highlightedCell: ChatMessageCell?
    
    private lazy var notiView: ChatNotiView = {
        let view = ChatNotiView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.clipsToBounds = true
        view.isHidden = true
        
        return view
    }()
    
    private lazy var replyView: ChatReplyView = {
        let view = ChatReplyView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.clipsToBounds = true
        view.isHidden = true
        
        return view
    }()
    
    private var settingPanelVC: ChatRoomSettingViewController?
    private var isHandlingRoomExit = false
    private lazy var dimView: UIView = {
        //        let v = UIControl(frame: .zero)
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = OutPickTheme.ColorToken.overlayScrim
        v.alpha = 0
        
        return v
    }()
    
    // 공지 배너 (고정/접기/만료 안내 지원)
    private lazy var announcementBanner: AnnouncementBannerView = {
        let v = AnnouncementBannerView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true
        v.onHeightChange = { [weak self] in
            guard let self = self else { return }
            self.adjustForBannerHeight()
        }
        
        // Long-press on the announcement banner (to show options or toggle expand)
        let bannerLongPress = UILongPressGestureRecognizer(target: self, action: #selector(handleAnnouncementBannerLongPress(_:)))
        bannerLongPress.minimumPressDuration = 0.35
        bannerLongPress.cancelsTouchesInView = true
        v.addGestureRecognizer(bannerLongPress)
        // Ensure the global long press (used for message cells) doesn't steal this interaction
        self.longPressGesture.require(toFail: bannerLongPress)
        return v
    }()
    private var baseTopInsetForBanner: CGFloat?
    
    // Delete confirm overlay
    private var confirmDimView: UIControl?
    private var confirmView: ConfirmView?
    
    private let imagesSubject = CurrentValueSubject<[UIImage], Never>([])
    private var imagesPublishser: AnyPublisher<[UIImage], Never> {
        return imagesSubject.eraseToAnyPublisher()
    }
    
    // Layout 제약 조건 저장
    private var chatConstraints: [NSLayoutConstraint] = []
    private var chatUIViewBottomConstraint: NSLayoutConstraint?
    private var chatMessageCollectionViewBottomConstraint: NSLayoutConstraint?
    private var joinConsraints: [NSLayoutConstraint] = []
    private var joinButtonConstraints: [NSLayoutConstraint] = []
    
    private var interactionController: UIPercentDrivenInteractiveTransition?
    
    private lazy var tapGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture))
        gesture.delegate = self
        gesture.cancelsTouchesInView = false
        return gesture
    }()
    
    lazy var longPressGesture: UILongPressGestureRecognizer = {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        gesture.delegate = self
        return gesture
    }()
    
    private var searchUIBottomConstraint: NSLayoutConstraint?
    
    private var scrollTargetIndex: IndexPath?
    
    private var lastContainerViewOriginY: Double = 0

    @MainActor
    private var isParticipantPreviewMode: Bool {
        guard let room else { return false }
        return chatRoomViewModel.isCurrentUserParticipant(in: room) == false
    }
    
    // MARK: - Profile sync
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.definesPresentationContext = true
        view.backgroundColor = OutPickTheme.ColorToken.backgroundBase
        
        configureDataSource()
        
        if isRoomSaving {
            LoadingIndicator.shared.start(on: self)
            chatUIView.isHidden = false
            joinRoomBtn.isHidden = true
        } else {
            LoadingIndicator.shared.stop()
        }
        
        view.addGestureRecognizer(tapGesture)
        view.addGestureRecognizer(longPressGesture)
        
        setupCustomNavigationBar()
        setupJoinRoomButtonIfNeeded()
        decideJoinUI()
        setupAttachmentView()
        
        setupInitialMessages()
        
        bindKeyboardPublisher()
        bindSearchEvents()
        bindRoomClosedEvent()
        bindAppLifecycleForLastRead()
        
        chatMessageCollectionView.delegate = self
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard isParticipantPreviewMode == false else { return }
        Task { @MainActor [chatRoomViewModel] in
            await chatRoomViewModel.handleRoomWillAppear()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isParticipantPreviewMode == false {
            Task { @MainActor [chatRoomViewModel] in
                await chatRoomViewModel.handleRoomWillDisappear()
            }
        }
        flushLastReadSeq(trigger: "viewWillDisappear")
        needsTransientBindingsRestore = !(self.isMovingFromParent || self.isBeingDismissed)
        
        isUserInCurrentRoom = false
        stopRoomMessageStream()
        
        if let room = self.room {
            if ChatViewController.currentRoomID == room.ID {
                ChatViewController.currentRoomID = nil    // ✅ 나갈 때 초기화
            }
        }
        
        stopAllPrefetchers()
        initialLoadTask?.cancel()
        initialLoadTask = nil
        chatRoomViewModel.cancelSearchWork()
        searchJumpTask?.cancel()
        searchJumpTask = nil
        cancellables.removeAll()
        
        convertImagesTask?.cancel()
        convertVideosTask?.cancel()
        profileSyncManager.reset()
        removeReadMarkerIfNeeded()
        
        // 참여하지 않은 방이면 로컬 메시지 삭제 처리 (메인 바깥에서 비동기 실행)
        if let room = self.room,
           !chatRoomViewModel.isCurrentUserParticipant(in: room) {
            let roomID = room.ID ?? ""
            Task(priority: .utility) { [chatRoomViewModel] in
                await chatRoomViewModel.cleanTransientLocalRoomData(roomID: roomID)
            }
        }
        
        self.navigationController?.setNavigationBarHidden(true, animated: false)
        
        // push로 다른 화면을 덮은 게 아니라,
        // 네비게이션에서 빠져나가거나 dismiss 된 경우에만 true
        if self.isMovingFromParent || self.isBeingDismissed {
            stopRoomClosedObservation()
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.notiView.layer.cornerRadius = 15
    }
    
    //MARK: 메시지 관련
    @MainActor
    private func setupInitialMessages() {
        initialLoadTask?.cancel()
        initialLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let room = self.room else { return }
            let isParticipant = self.chatRoomViewModel.isCurrentUserParticipant(in: room)
            LoadingIndicator.shared.start(on: self)

            var didStopLoading = false
            func stopLoadingIfNeeded() {
                guard !didStopLoading else { return }
                didStopLoading = true
                LoadingIndicator.shared.stop()
            }

            for await event in self.chatRoomViewModel.startInitialLoadEvents(isParticipant: isParticipant) {
                if Task.isCancelled { break }

                switch event {
                case .phaseChanged(let phase):
                    switch phase {
                    case .localVisible, .offlineNoLocal, .ready:
                        stopLoadingIfNeeded()
                    case .failed(let message):
                        stopLoadingIfNeeded()
                        print("❌ 메시지 초기화 실패:", message)
                    case .idle, .checkingNetwork, .loadingLocal, .serverSyncing:
                        break
                    }

                case .render(let command):
                    switch command {
                    case .replaceWindow(let window):
                        self.setCenteredStatusMessage(nil)
                        self.setMessageWindow(window)
                        stopLoadingIfNeeded()

                    case .reloadDeleted(let messages):
                        self.addMessages(messages, updateType: .reload)

                    case .showCenteredMessage(let message):
                        self.setCenteredStatusMessage(message)
                        stopLoadingIfNeeded()

                    case .hideCenteredMessage:
                        self.setCenteredStatusMessage(nil)
                    }

                case .warmMedia(let messages, let maxConcurrent):
                    self.scheduleInitialMediaWarmup(for: messages, maxConcurrent: maxConcurrent)

                case .participantSessionReady(_, let bindRealtime):
                    self.isUserInCurrentRoom = true
                    if bindRealtime {
                        self.bindMessagePublishers()
                    }

                case .completed:
                    stopLoadingIfNeeded()
                }
            }

            stopLoadingIfNeeded()
        }
    }

    @MainActor
    private func setCenteredStatusMessage(_ message: String?) {
        let isVisible = !(message?.isEmpty ?? true)
        centeredStatusLabel.text = message
        centeredStatusLabel.isHidden = !isVisible
        chatMessageCollectionView.backgroundView?.isHidden = !isVisible
    }

    @MainActor
    private func setMessageWindow(_ window: ChatInitialWindow) {
        let items = messageWindowStore.reset(
            messages: window.messages,
            readBoundarySeq: window.readBoundarySeq
        )

        applyWindowSnapshot(items, animatingDifferences: false)
        scheduleProfileCacheRefresh(for: messageWindowStore.visibleMessages)

        if window.readBoundarySeq != nil {
            scrollToReadMarkerIfNeeded()
        } else {
            chatMessageCollectionView.scrollToBottom()
        }
    }

    @MainActor
    private func scrollToReadMarkerIfNeeded() {
        chatMessageCollectionView.layoutIfNeeded()
        let items = dataSource.snapshot().itemIdentifiers(inSection: .main)
        guard let index = items.firstIndex(where: {
            if case .readMarker = $0 { return true }
            return false
        }) else { return }
        chatMessageCollectionView.scrollToMessage(at: IndexPath(item: index, section: 0))
    }

    private func scheduleInitialMediaWarmup(for messages: [ChatMessage], maxConcurrent: Int) {
        guard !messages.isEmpty else { return }
        let concurrency = max(1, maxConcurrent)
        let roomID = room?.ID ?? ""
        let thumbnailMessages = messages.filter {
            $0.hasDisplayableAttachments
        }
        let videoMessages = messages.filter { $0.hasDisplayableVideos }

        Task(priority: .utility) { [weak self] in
            guard let self else { return }

            if !thumbnailMessages.isEmpty {
                var index = 0
                while index < thumbnailMessages.count {
                    let end = min(index + concurrency, thumbnailMessages.count)
                    let slice = Array(thumbnailMessages[index..<end])
                    await withTaskGroup(of: Void.self) { group in
                        for msg in slice {
                            group.addTask { [weak self] in
                                guard let self else { return }
                                _ = await self.attachmentImageLoader.cacheImagesIfNeeded(
                                    for: msg,
                                    maxBytes: self.chatThumbnailMaxBytes
                                )
                                await MainActor.run {
                                    self.reloadVisibleMessageIfNeeded(messageID: msg.ID)
                                }
                            }
                        }
                        await group.waitForAll()
                    }
                    index = end
                }
            }

            if !roomID.isEmpty, !videoMessages.isEmpty {
                var index = 0
                while index < videoMessages.count {
                    let end = min(index + concurrency, videoMessages.count)
                    let slice = Array(videoMessages[index..<end])
                    await withTaskGroup(of: Void.self) { group in
                        for msg in slice {
                            group.addTask { [weak self] in
                                guard let self else { return }
                                await self.videoAssetLoader.cacheVideoAssetsIfNeeded(
                                    for: msg,
                                    maxThumbnailBytes: self.chatThumbnailMaxBytes
                                )
                                await MainActor.run {
                                    self.reloadVisibleMessageIfNeeded(messageID: msg.ID)
                                }
                            }
                        }
                        await group.waitForAll()
                    }
                    index = end
                }
            }
        }
    }
    
    @MainActor
    private func reloadVisibleMessageIfNeeded(messageID: String) {
        var snapshot = dataSource.snapshot()
        guard let item = snapshot.itemIdentifiers.first(where: { item in
            if case let .message(m) = item { return m.ID == messageID }
            return false
        }) else { return }
        snapshot.reconfigureItems([item])
        dataSource.apply(snapshot, animatingDifferences: false)
    }
    
    @MainActor
    private func removeReadMarkerIfNeeded() {
        var snapshot = dataSource.snapshot()
        if let marker = snapshot.itemIdentifiers.first(where: {
            if case .readMarker = $0 { return true }
            return false
        }) {
            _ = messageWindowStore.removeReadMarker()
            snapshot.deleteItems([marker])
            dataSource.apply(snapshot, animatingDifferences: false)
        }
    }
    
    @MainActor
    private func loadOlderMessages(before messageID: String?) async {
        do {
            let loadedMessages = try await chatRoomViewModel.loadOlderMessages(before: messageID)
            appendMessagesInChunks(loadedMessages, updateType: .older)
        } catch {
            print("❌ loadOlderMessages 실패:", error)
        }
    }
    
    @MainActor
    private func loadNewerMessagesIfNeeded(after messageID: String?) async {
        do {
            let result = try await chatRoomViewModel.loadNewerMessages(after: messageID)
            appendMessagesInChunks(result.bufferedMessagesToFlush, updateType: .newer)
            maybeUpdateLastReadSeq(trigger: "newerPage", skipNearBottomCheck: true)
            appendMessagesInChunks(result.messages, updateType: .newer)
        } catch {
            print("❌ loadNewerMessagesIfNeeded 실패:", error)
        }
    }

    @MainActor
    private func appendMessagesInChunks(_ messages: [ChatMessage], updateType: MessageUpdateType) {
        guard !messages.isEmpty else { return }
        let chunkSize = 20
        let total = messages.count
        for i in stride(from: 0, to: total, by: chunkSize) {
            let end = min(i + chunkSize, total)
            let chunk = Array(messages[i..<end])
            addMessages(chunk, updateType: updateType)
        }
    }
    
    @MainActor
    private func bindMessagePublishers() {
        guard let room = self.room else { return }
        let roomID = room.ID ?? ""
        guard !roomID.isEmpty else { return }

        // Prevent duplicate subscriptions for the same room on repeated UI setup/binding paths.
        guard realtimeSubscription?.roomID != roomID else { return }

        stopRoomMessageStream()
        startRoomMessageStream(for: roomID)

        let cancellable = chatRoomViewModel.setupDeletionListener { [weak self] deletedMessageID in
            guard let self = self else { return }
            Task { @MainActor in
                var toReloadIDs = Set<String>()

                if self.messageWindowStore.updateMessage(id: deletedMessageID, mutate: { message in
                    message.isDeleted = true
                }) != nil {
                    toReloadIDs.insert(deletedMessageID)
                } else {
                    print("⚠️ deleted message not in window: \(deletedMessageID)")
                }

                let updatedReplies = self.messageWindowStore.updateMessages(where: {
                    $0.replyPreview?.messageID == deletedMessageID
                }) { reply in
                    reply.replyPreview?.isDeleted = true
                }
                toReloadIDs.formUnion(updatedReplies.map(\.ID))

                if !toReloadIDs.isEmpty {
                    self.reconfigureMessageItems(messageIDs: toReloadIDs)
                }
            }
        }
        cancellable.store(in: &cancellables)
    }

    @MainActor
    private func startRoomMessageStream(for roomID: String) {
        let subscription = ChatRoomRealtimeSubscription(
            roomID: roomID,
            openSession: { [chatRoomViewModel] in
                try await chatRoomViewModel.openMessageStream(roomID: roomID)
            },
            onMessage: { [weak self] receivedMessage in
                guard let self else { return }
                await self.handleIncomingMessage(receivedMessage)
            },
            onFailure: { error in
                #if DEBUG
                print("[ChatViewController] realtime stream failed roomID=\(roomID): \(error)")
                #endif
            },
            onFinish: { [weak self] finishedSubscription in
                guard let self,
                      self.realtimeSubscription === finishedSubscription else { return }
                self.realtimeSubscription = nil
            }
        )

        realtimeSubscription = subscription
        subscription.start()
    }

    @MainActor
    private func stopRoomMessageStream() {
        realtimeSubscription?.stop()
        realtimeSubscription = nil
    }
    
    // 수신 메시지를 저장 및 UI 반영
    @MainActor
    private func handleIncomingMessage(_ message: ChatMessage) async {
        guard self.room != nil else { return }
        if message.roomID != chatRoomViewModel.roomID { return }

        // 1) 첨부 캐시 선행
        let hasImages = message.hasDisplayableImages
        let hasVideos = message.hasDisplayableVideos
        if hasImages || hasVideos {
            await withTaskGroup(of: Void.self) { group in
                if hasImages || hasVideos {
                    group.addTask { [weak self] in
                        guard let self = self else { return }
                        _ = await self.attachmentImageLoader.cacheImagesIfNeeded(
                            for: message,
                            maxBytes: self.chatThumbnailMaxBytes
                        )
                        await MainActor.run {
                            self.reloadVisibleMessageIfNeeded(messageID: message.ID)
                        }
                    }
                }
                if hasVideos {
                    group.addTask { [weak self] in
                        guard let self = self else { return }
                        await self.videoAssetLoader.cacheVideoAssetsIfNeeded(
                            for: message,
                            maxThumbnailBytes: self.chatThumbnailMaxBytes
                        )
                    }
                }
                await group.waitForAll()
            }
        }

        switch chatRoomViewModel.handleIncomingMessage(message) {
        case .buffered:
            return
        case .append:
            scheduleProfileCacheRefresh(for: [message])
            addMessages([message])
            maybeUpdateLastReadSeq(trigger: "liveIncoming")
        }

        Task(priority: .userInitiated) {
            do {
                try await self.chatRoomViewModel.persistIncomingMessage(message)
                await self.outgoingOutboxUseCase.completeServerConfirmedMessage(message)
            } catch {
                print("❌ 메시지 저장 실패: \(error)")
            }
        }
    }
    
    // MARK: LocalChatUser + Profile sync 관련 함수
    @MainActor
    private func scheduleProfileCacheRefresh(for messages: [ChatMessage]) {
        guard !messages.isEmpty else { return }
        Task(priority: .utility) { [weak self, profileSyncManager] in
            let changedUserIDs = await profileSyncManager.refreshProfiles(from: messages)
            guard !changedUserIDs.isEmpty else { return }

            await MainActor.run {
                self?.applyProfileRefresh(changedUserIDs: changedUserIDs)
            }
        }
    }

    @MainActor
    private func applyProfileRefresh(changedUserIDs: Set<String>) {
        let normalizedUserIDs = Set(
            changedUserIDs
                .map { normalizedProfileUID($0) }
                .filter { !$0.isEmpty && !$0.contains("/") }
        )
        guard !normalizedUserIDs.isEmpty else { return }

        let updatedMessages = messageWindowStore.updateMessages(where: { message in
            normalizedUserIDs.contains(normalizedProfileUID(message.senderUID))
        }, mutate: { [profileSyncManager] message in
            guard let profile = profileSyncManager.profile(for: message.senderUID) else { return }
            let nickname = profile.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
            if !nickname.isEmpty {
                message.senderNickname = nickname
            }
            message.senderAvatarPath = profile.profileImagePath
        })

        let messageIDs = Set(updatedMessages.map(\.ID))
        guard !messageIDs.isEmpty else { return }
        reconfigureMessageItems(messageIDs: messageIDs)
    }

    private func normalizedProfileUID(_ uid: String) -> String {
        uid.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func setupChatUI() {
        // 이전 상태(참여 전)에 설정된 제약을 정리하기 위해, 중복 추가를 방지하고 기존 제약과 충돌하지 않도록 제거
        if chatMessageCollectionView.superview != nil {
            chatMessageCollectionView.removeFromSuperview()
        }
        if chatUIView.superview != nil {
            chatUIView.removeFromSuperview()
        }
        
        view.addSubview(chatUIView)
        chatUIView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(chatMessageCollectionView)
        chatMessageCollectionView.translatesAutoresizingMaskIntoConstraints = false
        chatUIView.backgroundColor = OutPickTheme.ColorToken.backgroundBase
        chatMessageCollectionView.backgroundColor = OutPickTheme.ColorToken.backgroundBase
        
        chatUIViewBottomConstraint = chatUIView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        NSLayoutConstraint.deactivate(chatConstraints)
        chatConstraints = [
            chatUIView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chatUIView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chatUIViewBottomConstraint!,
            chatUIView.heightAnchor.constraint(greaterThanOrEqualToConstant: chatUIView.minHeight),
            
            chatMessageCollectionView.topAnchor.constraint(equalTo: customNavigationBar.bottomAnchor),
            chatMessageCollectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chatMessageCollectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chatMessageCollectionView.bottomAnchor.constraint(equalTo: chatUIView.topAnchor),
        ]
        NSLayoutConstraint.activate(chatConstraints)
        
        view.bringSubviewToFront(chatUIView)
        view.bringSubviewToFront(customNavigationBar)
        chatMessageCollectionView.contentInset.top = 5
        chatMessageCollectionView.verticalScrollIndicatorInsets.top = 5
        chatMessageCollectionView.contentInset.bottom = 5
        chatMessageCollectionView.verticalScrollIndicatorInsets.bottom = 5
        
        NSLayoutConstraint.deactivate(joinConsraints)
        setupCopyReplyDeleteView()
    }
    
    @MainActor
    private func handleSendButtonTap() {
        guard isParticipantPreviewMode == false else { return }
        guard let message = self.chatUIView.messageTextView.text,
              let outgoingMessage = chatRoomViewModel.makeOutgoingTextMessage(
                text: message,
                replyPreview: replyMessage
              ) else { return }
        
        self.chatUIView.messageTextView.text = nil
        self.chatUIView.updateHeight()
        self.chatUIView.sendButton.isEnabled = false
        self.chatUIView.applySendButtonState()
        
        // Optimistic render: sender sees the message immediately.
        addMessages([outgoingMessage], updateType: .newer)
        chatMessageCollectionView.scrollToBottom()
        
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.chatRoomViewModel.sendPreparedMessage(outgoingMessage)
            } catch {
                await self.outgoingOutboxUseCase.stageTextMessage(outgoingMessage)
                await MainActor.run {
                    self.markMessageSendFailed(messageID: outgoingMessage.ID)
                }
            }
        }
        
        if self.replyMessage != nil {
            self.replyMessage = nil
            self.replyView.isHidden = true
        }
    }
    
    //MARK: 첨부파일 관련
    @MainActor
    private func hideOrShowOptionMenu() {
        guard let image = self.chatUIView.attachmentButton.imageView?.image else { return }
        if image != UIImage(systemName: "xmark") {
            self.chatUIView.attachmentButton.setImage(UIImage(systemName: "xmark"), for: .normal)
            
            if self.chatUIView.messageTextView.isFirstResponder {
                self.chatUIView.messageTextView.resignFirstResponder()
            }
            
            self.attachmentView.isHidden = false
            self.attachmentView.alpha = 1
            
            self.chatUIViewBottomConstraint?.constant = -(self.attachmentView.frame.height + 10)
        } else {
            self.chatUIView.attachmentButton.setImage(UIImage(systemName: "plus"), for: .normal)
            self.attachmentView.isHidden = true
            self.attachmentView.alpha = 0
            
            self.chatUIViewBottomConstraint?.constant = -10
        }
    }

    private func openCamera() {
        guard isParticipantPreviewMode == false else { return }
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            let imagePicker = UIImagePickerController()
            imagePicker.delegate = self
            imagePicker.allowsEditing = true
            imagePicker.sourceType = .camera
            
            present(imagePicker, animated: true, completion: nil)
        }
    }
    
    private func openPHPicker() {
        guard isParticipantPreviewMode == false else { return }
        var configuration = PHPickerConfiguration()
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = 0
        configuration.selection = .ordered
        configuration.preferredAssetRepresentationMode = .current
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }
    
    private func setupAttachmentView() {
        DispatchQueue.main.async {
            self.view.addSubview(self.attachmentView)
            
            NSLayoutConstraint.activate([
                self.attachmentView.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor),
                self.attachmentView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 20),
                self.attachmentView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20),
                self.attachmentView.heightAnchor.constraint(equalToConstant: 100),
            ])
        }
    }
    
    @MainActor
    private func handleAttachmentButtonTap(identifier: String) {
        guard isParticipantPreviewMode == false else { return }
        switch identifier {
        case "photo":
            print("Photo btn tapped!")
            self.hideOrShowOptionMenu()
            self.openPHPicker()
            
        case "camera":
            print("Camera btn tapped!")
            self.hideOrShowOptionMenu()
            self.openCamera()
            
        case "attachmentButton":
            self.hideOrShowOptionMenu()
            
        case "sendButton":
            self.handleSendButtonTap()
        default:
            return
        }
    }
    
    // MARK: 방 관련
    // Prevent duplicated join flow / duplicated loading HUDs
    private var isJoiningRoom: Bool = false
    
    private func bindRoomClosedEvent() {
        stopRoomClosedObservation()
        guard isParticipantPreviewMode == false else { return }
        roomClosedSubscription = chatRoomViewModel.observeRoomClosed { [weak self] roomID in
            guard let self else { return }
            self.router?.handleRoomExit(from: self, roomID: roomID)
        }
    }
    
    private func stopRoomClosedObservation() {
        roomClosedSubscription?.stop()
        roomClosedSubscription = nil
    }
    
    @MainActor
    private func restoreTransientBindingsIfNeeded() {
        bindSearchEvents()

        guard let room = room,
              chatRoomViewModel.isCurrentUserParticipant(in: room) else {
            return
        }

        scheduleProfileCacheRefresh(for: messageWindowStore.visibleMessages)
        bindMessagePublishers()
    }
    
    /// 방 정보(old → new) 변경점을 비교하고 필요한 UI/동기화만 수행
    @MainActor
    private func applyRoomDiffs(old: ChatRoom?, new: ChatRoom) async {
        // 최초 바인딩 또는 이전 정보가 없을 때: 전체 초기화 느낌으로 처리
        guard let old = old else {
            updateNavigationTitle(with: new)
            setupAnnouncementBannerIfNeeded()
            updateAnnouncementBanner(with: new.activeAnnouncement)
            return
        }
        
        // 1) 타이틀/참여자 수 변경 시 상단 네비바만 갱신
        if old.roomName != new.roomName || old.memberCount != new.memberCount {
            updateNavigationTitle(with: new)
        }
        
        // 2) 공지 변경 감지: ID/업데이트 시각/본문/작성자 중 하나라도 달라지면 배너 갱신
        let announcementChanged: Bool = {
            if old.activeAnnouncementID != new.activeAnnouncementID { return true }
            if old.announcementUpdatedAt != new.announcementUpdatedAt { return true }
            if old.activeAnnouncement?.text != new.activeAnnouncement?.text { return true }
            if old.activeAnnouncement?.authorID != new.activeAnnouncement?.authorID { return true }
            return false
        }()
        if announcementChanged {
            setupAnnouncementBannerIfNeeded()
            updateAnnouncementBanner(with: new.activeAnnouncement)
        }
    }
    
    @MainActor
    func handleRoomCreationSaveCompleted(savedRoom: ChatRoom) {
        chatRoomViewModel.handleRoomSaveCompleted(savedRoom)
        room = chatRoomViewModel.room
        isRoomSaving = false
        updateNavigationTitle(with: savedRoom)
        LoadingIndicator.shared.stop()
        view.isUserInteractionEnabled = true
    }

    // MARK: 초기 UI 설정 관련
    @MainActor
    private func decideJoinUI() {
        let currentRoom = chatRoomViewModel.room
        
        if chatRoomViewModel.isCurrentUserParticipant {
            setupChatUI()
            chatUIView.isHidden = false
            joinRoomBtn.isHidden = true
            self.setupAnnouncementBannerIfNeeded()
            self.updateAnnouncementBanner(with: currentRoom.activeAnnouncement)
        } else {
            setJoinRoombtn()
            joinRoomBtn.isHidden = false
            chatUIView.isHidden = true
            self.customNavigationBar.rightStack.isUserInteractionEnabled = false
        }
        
        updateNavigationTitle(with: currentRoom)
    }
    
    @MainActor
    private func setupJoinRoomButtonIfNeeded() {
        if joinRoomBtn.superview == nil {
            joinRoomBtn.translatesAutoresizingMaskIntoConstraints = false
            joinRoomBtn.setTitle("채팅 참여하기", for: .normal)
            joinRoomBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
            joinRoomBtn.setTitleColor(OutPickTheme.ColorToken.backgroundBase, for: .normal)
            joinRoomBtn.backgroundColor = OutPickTheme.ColorToken.accent
            joinRoomBtn.clipsToBounds = true
            joinRoomBtn.layer.cornerRadius = 20
            joinRoomBtn.isHidden = true
            joinRoomBtn.addTarget(self, action: #selector(joinRoomBtnTapped(_:)), for: .touchUpInside)
            view.addSubview(joinRoomBtn)
        }
        
        if joinButtonConstraints.isEmpty {
            joinButtonConstraints = [
                joinRoomBtn.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 10),
                joinRoomBtn.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -10),
                joinRoomBtn.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
                joinRoomBtn.heightAnchor.constraint(equalToConstant: 50)
            ]
            NSLayoutConstraint.activate(joinButtonConstraints)
        }
        
        view.bringSubviewToFront(joinRoomBtn)
        view.bringSubviewToFront(customNavigationBar)
    }
    
    private func setJoinRoombtn() {
        self.joinRoomBtn.clipsToBounds = true
        self.joinRoomBtn.layer.cornerRadius = 20
        self.joinRoomBtn.backgroundColor = OutPickTheme.ColorToken.accent
        self.joinRoomBtn.setTitleColor(OutPickTheme.ColorToken.backgroundBase, for: .normal)
        
        if chatMessageCollectionView.superview == nil {
            view.addSubview(chatMessageCollectionView)
            chatMessageCollectionView.translatesAutoresizingMaskIntoConstraints = false
            chatMessageCollectionView.backgroundColor = OutPickTheme.ColorToken.backgroundBase
            
            NSLayoutConstraint.activate([
                chatMessageCollectionView.topAnchor.constraint(equalTo: customNavigationBar.bottomAnchor),
                chatMessageCollectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                chatMessageCollectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
        }
        
        NSLayoutConstraint.deactivate(chatConstraints)
        
        joinConsraints = [
            chatMessageCollectionView.bottomAnchor.constraint(equalTo: joinRoomBtn.topAnchor)
        ]
        NSLayoutConstraint.activate(joinConsraints)
    }
    
    @MainActor
    @objc private func joinRoomBtnTapped(_ sender: UIButton) {
        // Prevent double taps / duplicated HUDs
        guard !isJoiningRoom else { return }
        isJoiningRoom = true

        LoadingIndicator.shared.stop()
        LoadingIndicator.shared.start(on: self)

        joinRoomBtn.isHidden = true
        customNavigationBar.rightStack.isUserInteractionEnabled = true

        NSLayoutConstraint.deactivate(joinConsraints)
        joinConsraints.removeAll()
        if chatMessageCollectionView.superview != nil {
            chatMessageCollectionView.removeFromSuperview()
        }

        Task {
            do {
                let updated = try await self.chatRoomViewModel.joinCurrentRoom()
                self.room = updated
                
                await MainActor.run {
                    self.setupChatUI()
                    self.chatUIView.isHidden = false
                    self.chatMessageCollectionView.isHidden = false
                    self.setupInitialMessages()
                    self.view.layoutIfNeeded()
                }
                self.isJoiningRoom = false
                print(#function, "✅ 방 참여 성공, UI 업데이트 완료")

            } catch {
                print("❌ 방 참여 처리 실패: \(error)")
                await MainActor.run {
                    self.joinRoomBtn.isHidden = false
                    self.customNavigationBar.rightStack.isUserInteractionEnabled = false
                    LoadingIndicator.shared.stop()
                    self.isJoiningRoom = false
                }
            }
        }
    }
    
    //MARK: 커스텀 내비게이션 바
    @MainActor
    @objc private func backButtonTapped() {
        guard let nav = self.navigationController else {
            if self.presentingViewController != nil {
                self.dismiss(animated: true)
            }
            return
        }

        // 바로 아래가 RoomCreateViewController이면, 그 이전 화면(또는 루트)로 복귀
        if let idx = nav.viewControllers.firstIndex(of: self), idx > 0, nav.viewControllers[idx-1] is RoomCreateViewController {
            if idx >= 2 {
                let target = nav.viewControllers[idx-2]
                nav.popToViewController(target, animated: true)
            } else {
                nav.popToRootViewController(animated: true)
            }
        } else {
            nav.popViewController(animated: true)
        }
    }

    @MainActor
    private func pruneRoomCreateFromNavStackIfNeeded() {
        guard let nav = self.navigationController,
              let idx = nav.viewControllers.firstIndex(of: self),
              idx > 0, nav.viewControllers[idx-1] is RoomCreateViewController else { return }
        var vcs = nav.viewControllers
        vcs.remove(at: idx-1)
        nav.setViewControllers(vcs, animated: false)
    }

    @MainActor
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if needsTransientBindingsRestore {
            restoreTransientBindingsIfNeeded()
            needsTransientBindingsRestore = false
        }
        
        if let room = self.room {
            ChatViewController.currentRoomID = room.ID
        } // ✅ 현재 방 ID 저장
        pruneRoomCreateFromNavStackIfNeeded()
    }
    
    @objc private func settingButtonTapped() {
        guard isParticipantPreviewMode == false else { return }
        guard room != nil, let router else {
            assertionFailure("ChatViewController requires ChatRoomRouting for settings navigation.")
            return
        }
        router.showSettings(from: self)
    }

    @MainActor
    func applyUpdatedRoom(_ updatedRoom: ChatRoom) {
        let previousRoom = room
        self.room = updatedRoom
        self.chatRoomViewModel.applyRoomUpdate(updatedRoom)
        self.updateNavigationTitle(with: updatedRoom)
        Task { @MainActor in
            await self.applyRoomDiffs(old: previousRoom, new: updatedRoom)
        }
    }

    @MainActor
    func presentSettingPanel(_ VC: ChatRoomSettingViewController) {
        guard settingPanelVC == nil else { return }
        self.detachInteractiveDismissGesture()
        settingPanelVC = VC
        
        if dimView.superview == nil {
            view.addSubview(dimView)
            
            let dimTap = UITapGestureRecognizer(target: self, action: #selector(didTapDimView))
            dimTap.cancelsTouchesInView = true
            dimView.addGestureRecognizer(dimTap)
            tapGesture.require(toFail: dimTap)
            
            NSLayoutConstraint.activate([
                dimView.topAnchor.constraint(equalTo: view.topAnchor),
                dimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                dimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                dimView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }
        
        addChild(VC)
        view.addSubview(VC.view)
        VC.didMove(toParent: self)
        
        let width = floor(view.bounds.width * 0.7)
        let height = view.bounds.height
        let targetX = view.bounds.width - width
        
        VC.view.layer.cornerRadius = 16
        VC.view.clipsToBounds = true
        VC.view.frame = CGRect(x: view.bounds.width, y: 0, width: width, height: height)
        
        UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseOut]) {
            self.dimView.alpha = 1
            VC.view.frame.origin.x = targetX
        }
    }
    
    @objc private func didTapDimView() {
        dismissSettingPanel()
    }
    
    @MainActor
    func dismissSettingPanel(completion: (() -> Void)? = nil) {
        guard let VC = settingPanelVC else {
            completion?()
            return
        }
        
        print(#function, "호출")
        
        VC.willMove(toParent: nil)
        UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseIn]) {
            self.dimView.alpha = 0
            VC.view.frame.origin.x = self.view.bounds.width
        } completion: { _ in
            VC.view.removeFromSuperview()
            VC.removeFromParent()
            self.settingPanelVC = nil
            completion?()
        }
        
    }

    @MainActor
    func isCurrentRoom(roomID: String) -> Bool {
        room?.ID == roomID
    }

    @MainActor
    func dismissSettingPanelAndCloseRoom() {
        guard !isHandlingRoomExit else { return }
        isHandlingRoomExit = true

        dismissSettingPanel { [weak self] in
            self?.backButtonTapped()
        }
    }
    
    @MainActor
    private func updateNavigationTitle(with room: ChatRoom) {
        // ✅ 커스텀 내비게이션 바 타이틀 업데이트
        customNavigationBar.configureForChatRoom(
            roomTitle: room.roomName,
            participantCount: room.memberCount,
            target: self,
            onBack: #selector(backButtonTapped),
            onSearch: #selector(searchButtonTapped),
            onSetting: #selector(settingButtonTapped)
        )
    }
    
    //MARK: 대화 내용 검색
    private func bindSearchEvents() {
        customNavigationBar.searchKeywordPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] keyword in
                guard let self = self else { return }
                guard self.isParticipantPreviewMode == false else { return }
                
                self.clearPreviousHighlightIfNeeded()
                
                guard let keyword = keyword, !keyword.isEmpty else {
                    print(#function, "✅✅✅✅✅ keyword is empty ✅✅✅✅✅")
                    return
                }
                self.chatRoomViewModel.startSearch(containing: keyword) { [weak self] in
                    self?.applyHighlight()
                }
            }
            .store(in: &cancellables)
        
        customNavigationBar.cancelSearchPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self = self else { return }
                self.exitSearchMode()
            }
            .store(in: &cancellables)
        
    }

    private func makeSearchResultState() -> ChatSearchUIView.SearchResultState {
        let state = chatRoomViewModel.currentSearchDisplayState
        return ChatSearchUIView.SearchResultState(
            totalCount: state.totalCount,
            displayIndex: state.displayIndex,
            canMoveToPrevious: state.canMoveToPrevious,
            canMoveToNext: state.canMoveToNext
        )
    }
    
    @MainActor
    private func moveToMessageAndShake(_ idx: Int) {
        guard let message = chatRoomViewModel.searchMessage(at: idx) else { return }

        if let indexPath = indexPath(ofMessageID: message.ID) {
            if let cell = chatMessageCollectionView.cellForItem(at: indexPath) as? ChatMessageCell {
                cell.shakeHorizontally()
            } else {
                chatMessageCollectionView.scrollToMessage(at: indexPath)
                scrollTargetIndex = indexPath
            }
            return
        }

        searchJumpTask?.cancel()
        searchJumpTask = Task { [weak self] in
            guard let self else { return }
            do {
                let contextMessages = try await self.chatRoomViewModel.loadMessagesAroundSearchAnchor(
                    message,
                    beforeLimit: 60,
                    afterLimit: 60
                )
                if Task.isCancelled { return }

                await MainActor.run {
                    self.replaceVisibleMessageWindowForSearchJump(with: contextMessages)
                    self.chatRoomViewModel.applyVisibleWindowAfterSearchJump(contextMessages)

                    guard let targetIndexPath = self.indexPath(ofMessageID: message.ID) else { return }
                    if let cell = self.chatMessageCollectionView.cellForItem(at: targetIndexPath) as? ChatMessageCell {
                        cell.shakeHorizontally()
                    } else {
                        self.chatMessageCollectionView.scrollToMessage(at: targetIndexPath)
                        self.scrollTargetIndex = targetIndexPath
                    }
                }
            } catch {
                print("❌ 검색 점프 컨텍스트 로드 실패: \(error)")
            }
        }
    }

    @MainActor
    private func replaceVisibleMessageWindowForSearchJump(with messages: [ChatMessage]) {
        guard !messages.isEmpty else { return }

        // Reset snapshot/window state and rebuild around the anchor context.
        var emptySnapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        emptySnapshot.appendSections([.main])
        dataSource.apply(emptySnapshot, animatingDifferences: false)

        _ = messageWindowStore.reset(messages: [], readBoundarySeq: nil)
        scrollTargetIndex = nil

        addMessages(messages, updateType: .initial)
    }
    
    @MainActor
    private func applyHighlight() {
        let highlightedIDs = chatRoomViewModel.highlightedMessageIDs
        var snapshot = dataSource.snapshot()
        
        let itemsToRealod = snapshot.itemIdentifiers.compactMap { item -> Item? in
            if case let .message(message) = item, highlightedIDs.contains(message.ID){
                return .message(message)
            }
            return nil
        }
        
        if !itemsToRealod.isEmpty {
            snapshot.reconfigureItems(itemsToRealod)
            dataSource.apply(snapshot, animatingDifferences: false)
        }
        
        searchUI.updateSearchResult(makeSearchResultState())
        if let idx = chatRoomViewModel.currentFilteredMessageIndex { moveToMessageAndShake(idx) }
    }
    
    @MainActor
    private func clearPreviousHighlightIfNeeded() {
        searchJumpTask?.cancel()
        searchJumpTask = nil

        var snapshot = dataSource.snapshot()
        let previousHighlightedIDs = chatRoomViewModel.highlightedMessageIDs
        
        let itemsToReload = snapshot.itemIdentifiers.compactMap { item -> Item? in
            if case let .message(message) = item, previousHighlightedIDs.contains(message.ID) {
                return .message(message)
            }
            return nil
        }

        _ = chatRoomViewModel.clearSearch()
        scrollTargetIndex = nil
        
        if !itemsToReload.isEmpty {
            snapshot.reconfigureItems(itemsToReload)
            dataSource.apply(snapshot, animatingDifferences: false)
        }

        chatMessageCollectionView.visibleCells
            .compactMap { $0 as? ChatMessageCell }
            .forEach { $0.highlightKeyword(nil) }
        
        searchUI.updateSearchResult(makeSearchResultState())
    }
    
    @MainActor
    private func exitSearchMode() {
        // 🔹 Search UI 숨기고 Chat UI 복원
        self.searchUI.isHidden = true
        self.chatUIView.isHidden = false
        
        clearPreviousHighlightIfNeeded()
    }
    
    @MainActor
    private func setupSearchUI() {
        if searchUI.superview == nil {
            view.addSubview(searchUI)
            searchUIBottomConstraint = searchUI.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -10)
            
            NSLayoutConstraint.activate([
                searchUI.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                searchUI.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
                searchUIBottomConstraint!,
                searchUI.heightAnchor.constraint(equalToConstant: 50)
            ])
        }
    }
    
    @MainActor
    @objc private func searchButtonTapped() {
        guard isParticipantPreviewMode == false else { return }
        customNavigationBar.switchToSearchMode()
        setupSearchUI()
        
        searchUI.isHidden = false
        chatUIView.isHidden = true
    }
    
    private func indexPath(ofMessageID messageID: String) -> IndexPath? {
        let snapshot = dataSource.snapshot()
        let items = snapshot.itemIdentifiers(inSection: .main)
        if let row = items.firstIndex(where: { item in
            if case let .message(message) = item { return message.ID == messageID }
            return false
        }) {
            return IndexPath(item: row, section: 0)
        } else {
            return nil
        }
    }
    
    //MARK: 메시지 삭제/답장/복사 관련
    @MainActor
    private func showCustomMenu(at indexPath: IndexPath/*, aboveCell: Bool*/) {
        guard isParticipantPreviewMode == false else { return }
        guard let cell = chatMessageCollectionView.cellForItem(at: indexPath) as? ChatMessageCell,
              let item = dataSource.itemIdentifier(for: indexPath),
              case let .message(message) = item else { return }

        let latestMessage = messageWindowStore.message(for: message.ID) ?? message
        guard latestMessage.isDeleted == false else { return }
        
        // 1.셀 강조하기
        cell.setHightlightedOverlay(true)
        highlightedCell = cell
        
        // 셀의 bounds 기준으로 컬렉션뷰 내 프레임 계산
        let cellFrameInCollection = cell.convert(cell.bounds, to: chatMessageCollectionView/*.collectionView*/)
        let cellCenterY = cellFrameInCollection.midY
        
        // 컬렉션 뷰 기준 중앙 사용 (화면 절반)
        let screenMiddleY = chatMessageCollectionView.bounds.midY
        let showAbove: Bool = cellCenterY > screenMiddleY
        let policy = chatRoomViewModel.messageActionPolicy(for: latestMessage)
        chatCustomMenu.configure(menuConfiguration(for: policy))
        
        // 2.메뉴 위치를 셀 기준으로
        view.addSubview(chatCustomMenu)
        NSLayoutConstraint.activate([
            showAbove ? chatCustomMenu.bottomAnchor.constraint(equalTo: cell.referenceView.topAnchor, constant: -8) : chatCustomMenu.topAnchor.constraint(equalTo: cell.referenceView.bottomAnchor, constant: 8),
            
            chatRoomViewModel.isCurrentUser(latestMessage.senderUID) ? chatCustomMenu.trailingAnchor.constraint(equalTo: cell.referenceView.trailingAnchor, constant: 0) : chatCustomMenu.leadingAnchor.constraint(equalTo: cell.referenceView.leadingAnchor, constant: 0)
        ])
        
        // 3. 버튼 액션 설정
        setChatMenuActions(for: latestMessage, policy: policy)
    }
    
    private func menuConfiguration(for policy: ChatMessageActionPolicy) -> ChatCustomPopUpMenu.Configuration {
        ChatCustomPopUpMenu.Configuration(
            canReply: policy.canReply,
            canCopy: policy.canCopy,
            canDelete: policy.canDelete,
            canReport: policy.canReport,
            canAnnounce: policy.canAnnounce
        )
    }

    private func setChatMenuActions(for message: ChatMessage, policy: ChatMessageActionPolicy) {
        chatCustomMenu.onActionSelected = { [weak self] action in
            guard let self = self else { return }
            guard policy.allows(action) else {
                self.dismissCustomMenu()
                return
            }
            self.handleMessageMenuAction(action, message: message)
        }
    }
    
    @MainActor
    private func handleMessageMenuAction(_ action: ChatMessageAction, message: ChatMessage) {
        guard isParticipantPreviewMode == false else { return }
        switch action {
        case .reply:
            handleReply(message: message)
            dismissCustomMenu()
        case .copy:
            handleCopy(message: message)
            dismissCustomMenu()
        case .delete:
            if message.isFailed {
                ConfirmView.present(
                    in: view,
                    message: "전송 실패 메시지를 이 기기에서 삭제합니다.",
                    onConfirm: { [weak self] in
                        self?.performLocalFailedMessageDelete(message)
                    }
                )
            } else {
                ConfirmView.present(
                    in: view,
                    message: "삭제 시 모든 사용자의 채팅창에서 메시지가 삭제되며\n‘삭제된 메시지입니다.’로 표기됩니다.",
                    onConfirm: { [weak self] in
                        self?.performMessageServerAction(.delete, message: message)
                    }
                )
            }
            dismissCustomMenu()
        case .report:
            handleReport(message: message)
            dismissCustomMenu()
        case .announce:
            print(#function, "공지:", message.msg ?? "")
            ConfirmView.presentAnnouncement(in: view, onConfirm: { [weak self] in
                let authorID = self?.chatRoomViewModel.currentUserNickname ?? ""
                self?.performMessageServerAction(
                    .announce(authorID: authorID),
                    message: message,
                    successMessage: "공지를 등록했습니다.",
                    failureMessage: "공지 등록에 실패했습니다."
                )
            })
            dismissCustomMenu()
        }
    }

    @MainActor
    private func handleReport(message: ChatMessage) {
        print(#function, "신고:", message.msg ?? "")
        // 필요 시 UI 피드백
        showSuccess("메시지가 신고되었습니다.")
    }
    
    @MainActor
    private func handleReply(message: ChatMessage) {
        print(#function, "답장:", message)
        let replyText = message.isLookbookShareMessage ? message.lookbookSharePreviewText : (message.msg ?? "")
        self.replyMessage = ReplyPreview(messageID: message.ID, sender: message.senderNickname, text: replyText, isDeleted: false)
        replyView.configure(with: message)
        replyView.isHidden = false
    }
    
    private func handleCopy(message: ChatMessage) {
        UIPasteboard.general.string = message.msg
        print(#function, "복사:", message)
        // 필요 시 UI 피드백
        showSuccess("메시지가 복사되었습니다.")
    }
    
    private func performMessageServerAction(
        _ action: ChatMessageServerAction,
        message: ChatMessage,
        successMessage: String? = nil,
        failureMessage: String? = nil
    ) {
        guard isParticipantPreviewMode == false else { return }
        Task { @MainActor in
            do {
                try await self.chatRoomViewModel.performMessageServerAction(action, for: message)
                if let successMessage {
                    showSuccess(successMessage)
                }
            } catch {
                if let failureMessage {
                    showSuccess(failureMessage)
                }
                print("❌ 메시지 서버 액션 실패:", error)
            }
        }
    }

    @MainActor
    private func performLocalFailedMessageDelete(_ message: ChatMessage) {
        guard message.isFailed else { return }
        removeMessageFromWindow(messageID: message.ID)
        Task { [weak self] in
            guard let self else { return }
            await self.outgoingOutboxUseCase.deleteLocalFailedMessage(message)
        }
    }
    
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let location = gesture.location(in: chatMessageCollectionView)
        if let indexPath = chatMessageCollectionView.indexPathForItem(at: location) {
            guard let room = self.room,
                  chatRoomViewModel.isCurrentUserParticipant(in: room) else { return }
            showCustomMenu(at: indexPath)
        }
    }
    
    @objc private func handleAnnouncementBannerLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              isParticipantPreviewMode == false,
              let room = self.room,
              chatRoomViewModel.isCurrentUserAdmin(of: room) else { return }
        
        // 확인 팝업 → 삭제 실행
        ConfirmView.present(
            in: self.view,
            message: "현재 공지를 삭제할까요?\n삭제 시 모든 사용자의 배너에서 사라집니다.",
            style: .prominent,
            onConfirm: { [weak self] in
                guard let self = self else { return }
                Task { @MainActor in
                    do {
                        try await self.chatRoomViewModel.clearAnnouncement()
                        self.updateAnnouncementBanner(with: nil)   // 배너 숨김 + 인셋 복원
                        self.showSuccess("공지를 삭제했습니다.")
                    } catch {
                        self.showSuccess("공지 삭제에 실패했습니다.")
                        print("❌ 공지 삭제 실패:", error)
                    }
                }
            }
        )
    }
    
    private func dismissCustomMenu() {
        if let cell = highlightedCell { cell.setHightlightedOverlay(false) }
        highlightedCell = nil
        chatCustomMenu.onActionSelected = nil
        chatCustomMenu.removeFromSuperview()
    }
    
    @MainActor
    func showRoutingFailure(_ text: String) {
        showSuccess(text)
    }

    @MainActor
    private func showSuccess(_ text: String) {
        notiView.configure(text)
        
        if notiView.isHidden { notiView.isHidden = false }
        
        // 초기 상태: 보이지 않고, 약간 축소 상태
        self.notiView.alpha = 0
        self.notiView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        
        // fade-in + 확대 애니메이션
        UIView.animate(withDuration: 0.5, animations: {
            self.notiView.alpha = 1
            self.notiView.transform = .identity
        }) { _ in
            // fade-out만, scale 변화 없이 진행
            UIView.animate(withDuration: 0.5, delay: 0.6, options: [], animations: {
                self.notiView.alpha = 0
            }, completion: { _ in
                // 초기 상태로 transform은 유지 (확대 상태 유지)
                self.notiView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            })
        }
    }
    
    @MainActor
    private func setupAnnouncementBannerIfNeeded() {
        guard announcementBanner.superview == nil else { return }
        
        view.addSubview(announcementBanner)
        NSLayoutConstraint.activate([
            announcementBanner.topAnchor.constraint(equalTo: customNavigationBar.bottomAnchor),
            announcementBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            announcementBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        // 기본 인셋 저장 (최초 한 번)
        if baseTopInsetForBanner == nil {
            baseTopInsetForBanner = chatMessageCollectionView.contentInset.top
        }
        view.bringSubviewToFront(announcementBanner)
    }
    
    /// 현재 활성 공지 배너를 갱신 (고정 배너 사용)
    @MainActor
    private func updateAnnouncementBanner(with payload: AnnouncementPayload?) {
        setupAnnouncementBannerIfNeeded()
        
        guard let payload = payload else {
            // 공지 없음 → 배너 숨김 및 인셋 복원
            if !announcementBanner.isHidden {
                announcementBanner.isHidden = true
                view.layoutIfNeeded()
                adjustForBannerHeight()
            }
            return
        }
        // 배너 구성 및 표시
        announcementBanner.configure(text: payload.text,
                                     authorID: payload.authorID,
                                     createdAt: payload.createdAt,
                                     pinned: true)
        if announcementBanner.isHidden { announcementBanner.isHidden = false }
        view.layoutIfNeeded()
        adjustForBannerHeight()
    }
    
    @MainActor
    private func adjustForBannerHeight() {
        guard let base = baseTopInsetForBanner else { return }
        let height = announcementBanner.isHidden ? 0 : announcementBanner.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height
        let extra = height > 0 ? height + 8 : 0
        var inset = chatMessageCollectionView.contentInset
        inset.top = base + extra
        chatMessageCollectionView.contentInset = inset
        chatMessageCollectionView.verticalScrollIndicatorInsets.top = inset.top
    }
    
    private func setupCopyReplyDeleteView() {
        view.addSubview(notiView)
        NSLayoutConstraint.activate([
            notiView.widthAnchor.constraint(equalToConstant: UIScreen.main.bounds.width * 0.7),
            notiView.heightAnchor.constraint(equalTo: chatUIView.heightAnchor),
            
            notiView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            notiView.bottomAnchor.constraint(equalTo: chatUIView.topAnchor, constant: -10),
        ])
        view.bringSubviewToFront(notiView)
        
        view.addSubview(replyView)
        NSLayoutConstraint.activate([
            replyView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            replyView.bottomAnchor.constraint(equalTo: chatUIView.topAnchor, constant: -10),
            replyView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            replyView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            replyView.heightAnchor.constraint(equalToConstant: 43)
        ])
        view.bringSubviewToFront(replyView)
    }
    
    private func isCurrentUser(_ userID: String?) -> Bool {
        chatRoomViewModel.isCurrentUser(userID)
    }
    private func isCurrentUserAdmin(of room: ChatRoom) -> Bool {
        chatRoomViewModel.isCurrentUserAdmin(of: room)
    }

    @MainActor
    func stagePendingImageMessage(
        room: ChatRoom,
        roomID: String,
        messageID: String,
        pairs: [ProcessedImage]
    ) -> Bool {
        guard let pendingMessage = mediaUploadUseCase.makePendingImageMessage(
            roomID: roomID,
            messageID: messageID,
            pairs: pairs
        ) else {
            return false
        }
        guard pendingMediaUploadStore.stageImageUpload(
            room: room,
            roomID: roomID,
            messageID: messageID,
            pairs: pairs
        ) else {
            return false
        }

        addMessages([pendingMessage], updateType: .newer)
        reconfigureMessageItem(messageID: messageID)
        chatMessageCollectionView.scrollToBottom()
        return true
    }

    @MainActor
    func setPendingImageUploadState(_ state: PendingImageUploadState, for messageID: String) {
        pendingMediaUploadStore.setImageUploadState(state, for: messageID)
        _ = messageWindowStore.updateMessage(id: messageID) { message in
            message.isFailed = (state == .failed)
        }
        let updatedVisibleCell = updateVisibleOverlayIfPossible(messageID: messageID)
        switch state {
        case .uploading:
            // Avoid frequent cell reconfigure while progress ticks to prevent flicker.
            if !updatedVisibleCell {
                reconfigureMessageItem(messageID: messageID)
            }
        case .failed:
            reconfigureMessageItem(messageID: messageID)
        }
    }

    @MainActor
    func setUploadedImageAttachments(_ attachments: [Attachment], for messageID: String) {
        pendingMediaUploadStore.setUploadedImageAttachments(attachments, for: messageID)
    }

    @MainActor
    func stagedMessageForOutbox(messageID: String) -> ChatMessage? {
        messageWindowStore.message(for: messageID)
    }

    func stageOutgoingImageOutbox(message: ChatMessage, pairs: [ProcessedImage]) async {
        await outgoingOutboxUseCase.stageImageMessage(message, pairs: pairs)
    }

    func stageOutgoingVideoOutbox(message: ChatMessage, prepared: PreparedVideo) async {
        await outgoingOutboxUseCase.stageVideoMessage(message, prepared: prepared)
    }

    func markOutgoingImageUploadCompleted(messageID: String, attachments: [Attachment]) async {
        await outgoingOutboxUseCase.markImageUploadCompleted(messageID: messageID, attachments: attachments)
    }

    func markOutgoingVideoUploadCompleted(messageID: String, payload: VideoMetaPayload) async {
        await outgoingOutboxUseCase.markVideoUploadCompleted(messageID: messageID, payload: payload)
    }

    func markOutgoingMessageFailed(_ message: ChatMessage, error: Error?) async {
        await outgoingOutboxUseCase.markFailed(message: message, error: error)
    }

    @MainActor
    func stagePendingVideoMessage(
        roomID: String,
        messageID: String,
        prepared: PreparedVideo
    ) -> Bool {
        guard let pendingMessage = mediaUploadUseCase.makePendingVideoMessage(
            roomID: roomID,
            messageID: messageID,
            prepared: prepared
        ) else {
            return false
        }
        guard pendingMediaUploadStore.stageVideoUpload(
            roomID: roomID,
            messageID: messageID,
            prepared: prepared
        ) else {
            return false
        }

        addMessages([pendingMessage], updateType: .newer)
        reconfigureMessageItem(messageID: messageID)
        chatMessageCollectionView.scrollToBottom()
        return true
    }

    @MainActor
    func setPendingVideoUploadState(_ state: PendingImageUploadState, for messageID: String) {
        pendingMediaUploadStore.setVideoUploadState(state, for: messageID)
        _ = messageWindowStore.updateMessage(id: messageID) { message in
            message.isFailed = (state == .failed)
        }
        let updatedVisibleCell = updateVisibleOverlayIfPossible(messageID: messageID)
        if !updatedVisibleCell {
            reconfigureMessageItem(messageID: messageID)
        }
    }

    @MainActor
    func setUploadedVideoPayload(_ payload: VideoMetaPayload, for messageID: String) {
        pendingMediaUploadStore.setUploadedVideoPayload(payload, for: messageID)
    }

    @MainActor
    func schedulePendingImageUpload(room: ChatRoom, roomID: String, messageID: String, pairs: [ProcessedImage]) {
        let task = Task { [weak self] in
            guard let self else { return }
            await self.uploadPendingImageMessage(room: room, roomID: roomID, messageID: messageID, pairs: pairs)
            await MainActor.run {
                self.pendingMediaUploadStore.finishImageUploadTask(for: messageID)
            }
        }
        if !pendingMediaUploadStore.startImageUploadTask(task, for: messageID) {
            task.cancel()
        }
    }

    @MainActor
    func schedulePendingVideoUpload(roomID: String, messageID: String, prepared: PreparedVideo) {
        let task = Task { [weak self] in
            guard let self else { return }
            await self.uploadPendingVideoMessage(roomID: roomID, messageID: messageID, prepared: prepared)
            await MainActor.run {
                self.pendingMediaUploadStore.finishVideoUploadTask(for: messageID)
            }
        }
        if !pendingMediaUploadStore.startVideoUploadTask(task, for: messageID) {
            task.cancel()
        }
    }

    @MainActor
    func scheduleUploadedImageFinalize(room: ChatRoom, messageID: String, attachments: [Attachment]) {
        let task = Task { [weak self] in
            guard let self else { return }
            await self.finalizeUploadedImageMessage(room: room, messageID: messageID, attachments: attachments)
            await MainActor.run {
                self.pendingMediaUploadStore.finishImageUploadTask(for: messageID)
            }
        }
        if !pendingMediaUploadStore.startImageUploadTask(task, for: messageID) {
            task.cancel()
        }
    }

    @MainActor
    func scheduleUploadedVideoFinalize(roomID: String, messageID: String, payload: VideoMetaPayload) {
        let task = Task { [weak self] in
            guard let self else { return }
            await self.finalizeUploadedVideoMessage(roomID: roomID, messageID: messageID, payload: payload)
            await MainActor.run {
                self.pendingMediaUploadStore.finishVideoUploadTask(for: messageID)
            }
        }
        if !pendingMediaUploadStore.startVideoUploadTask(task, for: messageID) {
            task.cancel()
        }
    }

    @MainActor
    func markPendingImageUploadFailed(messageID: String) {
        setPendingImageUploadState(.failed, for: messageID)
    }

    @MainActor
    func markMessageSendFailed(messageID: String) {
        _ = messageWindowStore.updateMessage(id: messageID) { message in
            message.isFailed = true
        }
        reconfigureMessageItem(messageID: messageID)
    }

    @MainActor
    func finishPendingImageUpload(messageID: String) {
        pendingMediaUploadStore.completeImageUpload(for: messageID)
        if !updateVisibleOverlayIfPossible(messageID: messageID) {
            reconfigureMessageItem(messageID: messageID)
        }
    }

    @MainActor
    func finishPendingVideoUpload(messageID: String) {
        pendingMediaUploadStore.completeVideoUpload(for: messageID)
        if !updateVisibleOverlayIfPossible(messageID: messageID) {
            reconfigureMessageItem(messageID: messageID)
        }
    }

    @MainActor
    func markPendingVideoUploadFailed(messageID: String) {
        setPendingVideoUploadState(.failed, for: messageID)
    }

    func cleanupPendingImageOriginalFiles(_ pairs: [ProcessedImage]) {
        mediaUploadUseCase.cleanupImageOriginalFiles(pairs)
    }

    @MainActor
    private func confirmRetryUpload(for messageID: String) {
        guard isParticipantPreviewMode == false else { return }
        guard let message = messageWindowStore.message(for: messageID),
              message.isFailed else { return }
        ConfirmView.present(
            in: view,
            message: "전송 실패 메시지를 다시 보낼까요?",
            negativeTitle: "취소",
            positiveTitle: "재시도",
            style: .prominent,
            identifier: "RetryMessageConfirmView",
            onConfirm: { [weak self] in
                Task { @MainActor in
                    self?.retryPendingMediaUpload(for: messageID)
                }
            }
        )
    }

    @MainActor
    private func retryPendingMediaUpload(for messageID: String) {
        guard isParticipantPreviewMode == false else { return }
        guard let payload = pendingMediaUploadStore.mediaRetryPayload(for: messageID) else {
            retryOutgoingOutboxMessage(for: messageID)
            return
        }
        scheduleRetryPayload(payload)
    }

    @MainActor
    private func scheduleRetryPayload(_ payload: ChatPendingMediaRetryPayload) {
        switch payload {
        case .uploadImages(let payload):
            setPendingImageUploadState(.uploading(0), for: payload.messageID)
            schedulePendingImageUpload(
                room: payload.room,
                roomID: payload.roomID,
                messageID: payload.messageID,
                pairs: payload.pairs
            )
        case .finalizeImages(let room, _, let messageID, let attachments):
            setPendingImageUploadState(.uploading(1), for: messageID)
            scheduleUploadedImageFinalize(room: room, messageID: messageID, attachments: attachments)
        case .uploadVideo(let roomID, let messageID, let prepared):
            setPendingVideoUploadState(.uploading(0), for: messageID)
            schedulePendingVideoUpload(roomID: roomID, messageID: messageID, prepared: prepared)
        case .finalizeVideo(let roomID, let messageID, let payload):
            setPendingVideoUploadState(.uploading(1), for: messageID)
            scheduleUploadedVideoFinalize(roomID: roomID, messageID: messageID, payload: payload)
        }
    }

    @MainActor
    private func retryOutgoingOutboxMessage(for messageID: String) {
        guard isParticipantPreviewMode == false else { return }
        guard let room, let message = messageWindowStore.message(for: messageID) else { return }
        Task { [weak self] in
            guard let self else { return }
            guard let payload = await self.outgoingOutboxUseCase.retryPayload(for: message, room: room) else { return }
            await MainActor.run {
                self.scheduleOutgoingOutboxRetryPayload(payload)
            }
        }
    }

    @MainActor
    private func scheduleOutgoingOutboxRetryPayload(_ payload: ChatOutgoingOutboxRetryPayload) {
        switch payload {
        case .text(let message):
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.chatRoomViewModel.sendPreparedMessage(message)
                } catch {
                    await self.outgoingOutboxUseCase.markFailed(message: message, error: error)
                    await MainActor.run {
                        self.markMessageSendFailed(messageID: message.ID)
                    }
                }
            }

        case .uploadImages(let room, let messageID, let pairs):
            _ = pendingMediaUploadStore.stageImageUpload(
                room: room,
                roomID: room.ID ?? "",
                messageID: messageID,
                pairs: pairs
            )
            setPendingImageUploadState(.uploading(0), for: messageID)
            schedulePendingImageUpload(room: room, roomID: room.ID ?? "", messageID: messageID, pairs: pairs)

        case .finalizeImages(let room, let messageID, let attachments):
            _ = pendingMediaUploadStore.stageUploadedImageFinalize(
                room: room,
                roomID: room.ID ?? "",
                messageID: messageID,
                attachments: attachments
            )
            setPendingImageUploadState(.uploading(1), for: messageID)
            scheduleUploadedImageFinalize(room: room, messageID: messageID, attachments: attachments)

        case .uploadVideo(let roomID, let messageID, let prepared):
            _ = pendingMediaUploadStore.stageVideoUpload(roomID: roomID, messageID: messageID, prepared: prepared)
            setPendingVideoUploadState(.uploading(0), for: messageID)
            schedulePendingVideoUpload(roomID: roomID, messageID: messageID, prepared: prepared)

        case .finalizeVideo(let roomID, let messageID, let payload):
            _ = pendingMediaUploadStore.stageUploadedVideoFinalize(roomID: roomID, messageID: messageID, payload: payload)
            setPendingVideoUploadState(.uploading(1), for: messageID)
            scheduleUploadedVideoFinalize(roomID: roomID, messageID: messageID, payload: payload)
        }
    }

    private func pendingOverlayState(for messageID: String) -> ChatMessageCell.ImageUploadOverlayState? {
        guard let state = pendingMediaUploadStore.uploadState(for: messageID) else { return nil }
        switch state {
        case .uploading(let progress):
            return .uploading(progress)
        case .failed:
            return .failed
        }
    }

    @MainActor
    private func updateVisibleOverlayIfPossible(messageID: String) -> Bool {
        let snapshot = dataSource.snapshot()
        guard let itemIndex = snapshot.itemIdentifiers.firstIndex(where: { item in
            if case let .message(message) = item { return message.ID == messageID }
            return false
        }) else { return false }

        let indexPath = IndexPath(item: itemIndex, section: 0)
        guard let cell = chatMessageCollectionView.cellForItem(at: indexPath) as? ChatMessageCell else {
            return false
        }

        if let overlay = pendingOverlayState(for: messageID) {
            cell.applyImageUploadOverlay(overlay)
        } else {
            cell.applyImageUploadOverlay(.none)
        }
        return true
    }

    @MainActor
    private func reconfigureMessageItem(messageID: String) {
        reconfigureMessageItems(messageIDs: [messageID])
    }

    @MainActor
    private func reconfigureMessageItems(messageIDs: Set<String>) {
        var snapshot = dataSource.snapshot()
        let targets = snapshot.itemIdentifiers.filter { item in
            guard case let .message(message) = item else { return false }
            return messageIDs.contains(message.ID)
        }
        guard !targets.isEmpty else { return }
        snapshot.reconfigureItems(targets)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    @MainActor
    private func removeMessageFromWindow(messageID: String) {
        let mutation = messageWindowStore.removeMessage(id: messageID)
        applyWindowSnapshot(mutation.items, animatingDifferences: true)
    }
    
    //MARK: Diffable Data Source
    private func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: chatMessageCollectionView) { [unowned self] collectionView, indexPath, item in
            switch item {
            case .message(let message):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ChatMessageCell.reuseIdentifier, for: indexPath) as! ChatMessageCell
                
                // 메시지 최신 상태 반영
                let latestMessage = self.messageWindowStore.message(for: message.ID) ?? message
                
                if latestMessage.isLookbookShareMessage {
                    cell.configureWithLookbookShare(with: latestMessage, thumbnailLoader: { [weak self] path in
                        guard let self else { return nil }
                        return await self.lookbookShareThumbnailImage(for: path)
                    }, avatarLoader: { [weak self] path in
                        guard let self else { return nil }
                        return await self.avatarImage(for: path)
                    })
                } else if latestMessage.hasDisplayableAttachments {
                    cell.configureWithImage(with: latestMessage, thumbnailLoader: { [weak self] attachment in
                        guard let self else { return nil }
                        return await self.thumbnailImage(for: attachment)
                    }, avatarLoader: { [weak self] path in
                        guard let self else { return nil }
                        return await self.avatarImage(for: path)
                    })
                } else {
                    cell.configureWithMessage(with: latestMessage, avatarLoader: { [weak self] path in
                        guard let self else { return nil }
                        return await self.avatarImage(for: path)
                    })
                }
                if let state = self.pendingOverlayState(for: latestMessage.ID) {
                    cell.applyImageUploadOverlay(state)
                } else {
                    cell.applyImageUploadOverlay(.none)
                }
                
                cell.commands = ChatMessageCellCommands(
                    openMedia: { [weak self] messageID, attachmentIndex in
                        guard self?.isParticipantPreviewMode == false else { return }
                        self?.openMedia(messageID: messageID, attachmentIndex: attachmentIndex)
                    },
                    openSenderProfile: { [weak self] messageID in
                        guard self?.isParticipantPreviewMode == false else { return }
                        self?.openSenderProfile(messageID: messageID)
                    },
                    retryUpload: { [weak self] messageID in
                        guard let self else { return }
                        guard self.isParticipantPreviewMode == false else { return }
                        Task { @MainActor in
                            self.confirmRetryUpload(for: messageID)
                        }
                    },
                    openLookbookShare: { [weak self] sharedContent in
                        guard self?.isParticipantPreviewMode == false else { return }
                        self?.handleLookbookShareCardTap(sharedContent)
                    }
                )
                
                let keyword = (self.chatRoomViewModel.isHighlightedMessage(id: latestMessage.ID) == true)
                    ? self.chatRoomViewModel.currentSearchKeyword
                    : nil
                cell.highlightKeyword(keyword)
                
                return cell
            case .dateSeparator(let date):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: DateSeperatorCell.reuseIdentifier, for: indexPath) as! DateSeperatorCell
                
                let dateText = self.formatDateToDayString(date)
                cell.configureWithDate(dateText)
                
                return cell
                
            case .readMarker:
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: readMarkCollectionViewCell.reuseIdentifier, for: indexPath) as! readMarkCollectionViewCell
                
                cell.configure()
                return cell
            }
        }
        
        chatMessageCollectionView.setCollectionViewDataSource(dataSource)
        chatMessageCollectionView.prefetchDataSource = self
        if chatMessageCollectionView.backgroundView == nil {
            let container = UIView()
            container.addSubview(centeredStatusLabel)
            NSLayoutConstraint.activate([
                centeredStatusLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                centeredStatusLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                centeredStatusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 24),
                centeredStatusLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24)
            ])
            chatMessageCollectionView.backgroundView = container
            chatMessageCollectionView.backgroundView?.isHidden = true
        }
        applyWindowSnapshot([], animatingDifferences: false)
    }
    
    // MARK: - Diffable animation heuristics
    private func shouldAnimateDifferences(for updateType: MessageUpdateType, newItemCount: Int) -> Bool {
        switch updateType {
        case .newer:
            // 사용자가 거의 바닥(최근 메시지 근처)에 있고, 새 항목이 소량일 때만 애니메이션
            return newItemCount > 0 && newItemCount <= 20 && isNearBottom()
        case .older, .reload, .initial:
            return false
        }
    }
    
    private func isNearBottom(threshold: CGFloat = 120) -> Bool {
        let contentHeight = chatMessageCollectionView.contentSize.height
        let visibleMaxY = chatMessageCollectionView.contentOffset.y + chatMessageCollectionView.bounds.height
        return (contentHeight - visibleMaxY) <= threshold
    }
    
    @MainActor
    func addMessages(_ messages: [ChatMessage], updateType: MessageUpdateType = .initial) {
        guard !messages.isEmpty else { return }
        let windowSize = 300

        let mutation = messageWindowStore.apply(
            messages: messages,
            updateType: updateType,
            isUserInCurrentRoom: isUserInCurrentRoom,
            windowSize: windowSize
        )

        for replacement in mutation.replacements {
            mediaUploadUseCase.cleanupReplacedLocalPreviewFiles(
                previous: replacement.previous,
                next: replacement.next
            )
        }

        if updateType != .reload {
            scheduleProfileCacheRefresh(for: messages)
        }

        guard mutation.hasSnapshotChanges else { return }

        let animate = shouldAnimateDifferences(
            for: updateType,
            newItemCount: mutation.insertedItems.count
        )
        applyWindowSnapshot(
            mutation.items,
            reconfiguring: mutation.reconfiguredItems,
            animatingDifferences: animate
        )
    }

    private func applyWindowSnapshot(
        _ items: [Item],
        reconfiguring reconfiguredItems: [Item] = [],
        animatingDifferences: Bool
    ) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.main])
        snapshot.appendItems(items, toSection: .main)

        let visibleReconfiguredItems = reconfiguredItems.filter { items.contains($0) }
        if !visibleReconfiguredItems.isEmpty {
            snapshot.reconfigureItems(visibleReconfiguredItems)
        }

        dataSource.apply(snapshot, animatingDifferences: animatingDifferences)
    }
    
    // 캐시된 포맷터
    private lazy var dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy년 M월 d일 EEEE"
        return f
    }()
    private func formatDateToDayString(_ date: Date) -> String {
        return dayFormatter.string(from: date)
    }
    
    //MARK: Tap Gesture
    @MainActor
    @objc private func handleTapGesture() {
        
        if settingPanelVC != nil { return }
        view.endEditing(true)
        
        if !self.attachmentView.isHidden {
            chatUIView.attachmentButton.setImage(UIImage(systemName: "plus"), for: .normal)
            self.attachmentView.isHidden = true
            self.attachmentView.alpha = 0
            
            self.chatUIViewBottomConstraint?.constant = -10
            
            UIView.animate(withDuration: 0.25) {
                self.view.layoutIfNeeded()
            }
        }
        
        if chatCustomMenu.superview != nil {
            dismissCustomMenu()
        }
    }
    
    //MARK: 키보드 관련
    private func bindKeyboardPublisher() {
        NotificationCenter.default.publisher(for: UIApplication.keyboardWillShowNotification)
            .sink { [weak self] notification in
                guard let self = self else { return }
                self.keyboardWillShow(notification)
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.keyboardWillHideNotification)
            .sink { [weak self] notification in
                guard let self = self else { return }
                self.keyboardWillHide(notification)
            }
            .store(in: &cancellables)
    }
    
    @objc private func keyboardWillShow(_ sender: Notification) {
        guard let animationDuration = sender.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }
        
        // Hide attachment view if visible
        if !self.attachmentView.isHidden {
            self.attachmentView.isHidden = true
            self.chatUIView.attachmentButton.setImage(UIImage(systemName: "plus"), for: .normal)
            self.chatUIViewBottomConstraint?.constant = 0
        }
        UIView.animate(withDuration: animationDuration) {
            self.view.layoutIfNeeded()
        }
    }
    
    @objc private func keyboardWillHide(_ sender: Notification) {
        guard let animationDuration = sender.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }
        
        UIView.animate(withDuration: animationDuration) {
            self.view.layoutIfNeeded()
        }
    }
    
    //MARK: 기타
    private func showAlert(error: RoomCreationError) {
        var title: String
        var message: String
        
        switch error {
        case .saveFailed:
            title = "저장 실패"
            message = "채팅방 정보 저장에 실패했습니다. 다시 시도해주세요."
        case .imageUploadFailed:
            title = "이미지 업로드 실패"
            message = "방 이미지 업로드에 실패했습니다. 다시 시도해주세요."
        default:
            title = "오류"
            message = "알 수 없는 오류가 발생했습니다."
        }
        
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default) { [weak self] _ in
            guard let self = self else { return }
            guard let nav = self.navigationController, nav.viewControllers.count > 1 else {
                if self.presentingViewController != nil {
                    self.dismiss(animated: true)
                }
                return
            }
            nav.popViewController(animated: true)
        })
        present(alert, animated: true)
    }
    
    // MARK: 이미지 뷰어 관련
    // 이미지 뷰어 오픈 시 원본 프리패치 task
    private var imageViewerPrefetchTasks: [Task<Void, Never>] = []
    private let chatThumbnailMaxBytes = 4 * 1024 * 1024
    private let mediaPrefetchPad = 60
    private let mediaPrefetchCleanupDelayMs: UInt64 = 350
    
    // Thumbnail prefetch tasks for chat scrolling (path-based)
    private var thumbnailPrefetchTasks: [String: Task<Void, Never>] = [:]
    
    // Video asset warm-up tasks remain message-based.
    private var videoPrefetchTasks: [String: Task<Void, Never>] = [:]
    
    // Debounced cleanup task for cancelling prefetches that moved far outside visible range
    private var mediaPrefetchCleanupTask: Task<Void, Never>? = nil

    private func thumbnailImage(for attachment: Attachment) async -> UIImage? {
        for path in [attachment.pathThumb, attachment.pathOriginal] where !path.isEmpty {
            if let image = await attachmentImageLoader.cachedImage(for: path) {
                return image
            }
            if let image = try? await attachmentImageLoader.loadImage(for: path, maxBytes: chatThumbnailMaxBytes) {
                return image
            }
        }

        guard attachment.type == .video,
              !attachment.pathOriginal.isEmpty,
              let url = try? await resolveVideoURL(for: attachment.pathOriginal),
              let data = try? await videoThumbnailGenerator.thumbnailData(url: url, maxPixel: 360),
              let image = UIImage(data: data) else {
            return nil
        }
        return image
    }

    private func resolveVideoURL(for path: String) async throws -> URL {
        if let direct = URL(string: path),
           let scheme = direct.scheme?.lowercased(),
           ["http", "https", "file"].contains(scheme) {
            return direct
        }
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return try await storageURLResolver.url(for: path)
    }

    private func avatarImage(for path: String) async -> UIImage? {
        guard !path.isEmpty else { return nil }

        if let cached = await avatarImageManager.cachedAvatar(for: path) {
            return cached
        }

        return try? await avatarImageManager.loadAvatar(
            for: path,
            maxBytes: 3 * 1024 * 1024
        )
    }

    private func lookbookShareThumbnailImage(for path: String) async -> UIImage? {
        guard !path.isEmpty else { return nil }

        if let image = await attachmentImageLoader.cachedImage(for: path) {
            return image
        }

        return try? await attachmentImageLoader.loadImage(for: path, maxBytes: chatThumbnailMaxBytes)
    }

    @MainActor
    private func handleLookbookShareCardTap(_ sharedContent: LookbookSharedContent) {
        guard isParticipantPreviewMode == false else { return }
        guard let router else { return }
        router.openLookbookSharedContent(from: self, sharedContent: sharedContent)
    }

    @MainActor
    private func openMedia(messageID: String, attachmentIndex: Int) {
        guard isParticipantPreviewMode == false else { return }
        guard let currentMessage = messageForCommand(messageID: messageID) else { return }
        let attachments = currentMessage.displayableAttachments
        guard attachmentIndex >= 0, attachmentIndex < attachments.count else { return }
        let attachment = attachments[attachmentIndex]

        if attachment.type == .video {
            let path = attachment.pathOriginal
            guard !path.isEmpty, let router else { return }
            router.showVideoPlayer(from: self, path: path)
        } else {
            presentImageViewer(messageID: messageID, tappedIndex: attachmentIndex)
        }
    }

    @MainActor
    private func openSenderProfile(messageID: String) {
        guard isParticipantPreviewMode == false else { return }
        guard let currentMessage = messageForCommand(messageID: messageID) else { return }
        let senderUID = currentMessage.senderUID
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !senderUID.isEmpty else { return }

        router?.showUserProfile(
            from: self,
            userID: senderUID,
            nickname: currentMessage.senderNickname,
            avatarPath: currentMessage.senderAvatarPath
        )
    }

    @MainActor
    private func messageForCommand(messageID: String) -> ChatMessage? {
        if let message = messageWindowStore.message(for: messageID) {
            return message
        }

        return dataSource.snapshot().itemIdentifiers.compactMap { item in
            guard case .message(let message) = item, message.ID == messageID else {
                return nil
            }
            return message
        }.first
    }

    @MainActor
    private func visibleChatMessageCell(messageID: String) -> ChatMessageCell? {
        chatMessageCollectionView.visibleCells.compactMap { cell in
            guard let cell = cell as? ChatMessageCell,
                  cell.representedMessageID == messageID else {
                return nil
            }
            return cell
        }.first
    }

    @MainActor
    private func presentImageViewer(messageID: String, tappedIndex: Int) {
        guard let latestMessage = messageForCommand(messageID: messageID) else { return }
        let displayableAttachments = latestMessage.displayableAttachments
        guard tappedIndex >= 0, tappedIndex < displayableAttachments.count else { return }
        let tappedAttachment = displayableAttachments[tappedIndex]
        guard tappedAttachment.type == .image else { return }

        let imageEntries: [(mediaIndex: Int, attachment: Attachment)] = displayableAttachments.enumerated().compactMap { offset, attachment in
            guard attachment.type == .image else { return nil }
            return (offset, attachment)
        }
        guard !imageEntries.isEmpty else { return }

        let start = imageEntries.firstIndex { $0.mediaIndex == tappedIndex } ?? 0

        let previewImages = visibleChatMessageCell(messageID: messageID)?.currentPreviewImages() ?? []
        let pages: [SimpleImageViewerVC.ProgressivePage] = imageEntries.map { entry in
            let att = entry.attachment
            let thumbImage: UIImage?
            if entry.mediaIndex >= 0, entry.mediaIndex < previewImages.count {
                thumbImage = previewImages[entry.mediaIndex]
            } else {
                thumbImage = nil
            }

            let thumbnailPath: String?
            if !att.pathThumb.isEmpty {
                thumbnailPath = att.pathThumb
            } else if !att.pathOriginal.isEmpty {
                thumbnailPath = att.pathOriginal
            } else {
                thumbnailPath = nil
            }

            let originalPath = att.pathOriginal.isEmpty ? nil : att.pathOriginal
            return SimpleImageViewerVC.ProgressivePage(
                thumbnailImage: thumbImage,
                thumbnailPath: thumbnailPath,
                originalPath: originalPath
            )
        }
        guard !pages.isEmpty else { return }

        stopAllPrefetchers()

        router?.showImageViewer(
            from: self,
            pages: pages,
            startIndex: start,
            cachedImageProvider: { [weak self] path in
                guard let self else { return nil }
                return await self.attachmentImageLoader.cachedImage(for: path)
            },
            loadImageProvider: { [weak self] path, maxBytes in
                guard let self else { return nil }
                return try? await self.attachmentImageLoader.loadImage(for: path, maxBytes: maxBytes)
            }
        )

        let remoteOriginalIndexed: [(index: Int, path: String)] = pages.enumerated().compactMap { idx, page in
            guard let path = page.originalPath, !path.isEmpty else { return nil }
            if path.hasPrefix("/") || path.hasPrefix("file://") { return nil }
            return (idx, path)
        }
        guard !remoteOriginalIndexed.isEmpty else { return }

        let remoteStart = remoteOriginalIndexed.firstIndex { $0.index == start } ?? 0
        let order = ringOrderIndices(count: remoteOriginalIndexed.count, start: remoteStart)
        let prioritizedPaths = order.map { remoteOriginalIndexed[$0].path }

        let nearCount = min(8, prioritizedPaths.count)
        let nearPaths = Array(prioritizedPaths.prefix(nearCount))
        let restPaths = Array(prioritizedPaths.dropFirst(nearCount))

        let nearTask = Task(priority: .utility) { [weak self] in
            guard let self, !nearPaths.isEmpty else { return }
            await self.attachmentImageLoader.prefetchImages(
                paths: nearPaths,
                maxBytes: 60 * 1024 * 1024,
                maxConcurrent: 6
            )
        }
        imageViewerPrefetchTasks.append(nearTask)

        if !restPaths.isEmpty {
            let restTask = Task(priority: .background) { [weak self] in
                guard let self else { return }
                await self.attachmentImageLoader.prefetchImages(
                    paths: restPaths,
                    maxBytes: 60 * 1024 * 1024,
                    maxConcurrent: 3
                )
            }
            imageViewerPrefetchTasks.append(restTask)
        }
    }
    
    // Stop and clear all active image prefetch tasks
    private func stopAllPrefetchers() {
        imageViewerPrefetchTasks.forEach { $0.cancel() }
        imageViewerPrefetchTasks.removeAll()
    }

    @MainActor
    private func startMediaPrefetchIfNeeded(for message: ChatMessage, roomID: String) {
        for path in thumbnailPaths(for: message) {
            startThumbnailPrefetchIfNeeded(for: path)
        }

        let hasVideos = message.hasDisplayableVideos
        guard hasVideos else { return }
        startVideoPrefetchIfNeeded(for: message)
    }

    @MainActor
    private func startThumbnailPrefetchIfNeeded(for path: String) {
        guard !path.isEmpty else { return }
        guard thumbnailPrefetchTasks[path] == nil else { return }

        let task = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            if Task.isCancelled { return }

            _ = try? await self.attachmentImageLoader.loadImage(for: path, maxBytes: self.chatThumbnailMaxBytes)

            await MainActor.run {
                self.thumbnailPrefetchTasks[path] = nil
            }
        }

        thumbnailPrefetchTasks[path] = task
    }

    @MainActor
    private func startVideoPrefetchIfNeeded(for message: ChatMessage) {
        let messageID = message.ID
        guard videoPrefetchTasks[messageID] == nil else { return }

        let task = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            if Task.isCancelled { return }

            await self.videoAssetLoader.cacheVideoAssetsIfNeeded(
                for: message,
                maxThumbnailBytes: self.chatThumbnailMaxBytes
            )

            await MainActor.run {
                self.reloadVisibleMessageIfNeeded(messageID: message.ID)
                self.videoPrefetchTasks[messageID] = nil
            }
        }

        videoPrefetchTasks[messageID] = task
    }

    @MainActor
    private func cancelThumbnailPrefetchIfNeeded(for path: String) {
        thumbnailPrefetchTasks[path]?.cancel()
        thumbnailPrefetchTasks[path] = nil
    }

    @MainActor
    private func cancelVideoPrefetchIfNeeded(for messageID: String) {
        videoPrefetchTasks[messageID]?.cancel()
        videoPrefetchTasks[messageID] = nil
    }

    /// Debounced cleanup keeps nearby work alive during fast flicks instead of cancelling immediately.
    @MainActor
    private func scheduleMediaPrefetchCleanup(delayMs: UInt64 = 350, pad: Int = 60) {
        mediaPrefetchCleanupTask?.cancel()
        mediaPrefetchCleanupTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
            if Task.isCancelled { return }
            self.cleanupMediaPrefetchTasksOutsideVisibleRange(pad: pad)
        }
    }

    /// Cancel/remove path-based thumbnail tasks and message-based video warm-ups outside the visible window ± pad.
    @MainActor
    private func cleanupMediaPrefetchTasksOutsideVisibleRange(pad: Int = 60) {
        guard !thumbnailPrefetchTasks.isEmpty || !videoPrefetchTasks.isEmpty else { return }

        let snapshot = dataSource.snapshot()
        let items = snapshot.itemIdentifiers(inSection: .main)
        guard !items.isEmpty else {
            // Nothing to show -> cancel everything
            let thumbnailPaths = Array(thumbnailPrefetchTasks.keys)
            for path in thumbnailPaths { cancelThumbnailPrefetchIfNeeded(for: path) }
            let messageIDs = Array(videoPrefetchTasks.keys)
            for id in messageIDs { cancelVideoPrefetchIfNeeded(for: id) }
            return
        }

        // Build visible bounds (fallback to tail if nothing visible yet)
        let visibleItems = chatMessageCollectionView.indexPathsForVisibleItems
            .filter { $0.section == 0 }
            .map { $0.item }

        let total = items.count
        let lowerBound: Int
        let upperBound: Int

        if let minVis = visibleItems.min(), let maxVis = visibleItems.max() {
            lowerBound = max(0, minVis - pad)
            upperBound = min(total - 1, maxVis + pad)
        } else {
            let tail = max(0, total - 1)
            lowerBound = max(0, tail - pad)
            upperBound = tail
        }

        // Allowed message IDs and thumbnail paths within [lowerBound, upperBound]
        var allowedIDs = Set<String>()
        var allowedThumbnailPaths = Set<String>()
        allowedIDs.reserveCapacity((upperBound - lowerBound + 1) / 2)
        if lowerBound <= upperBound {
            for i in lowerBound...upperBound {
                if case let .message(m) = items[i] {
                    let latest = messageWindowStore.message(for: m.ID) ?? m
                    allowedIDs.insert(latest.ID)
                    for path in thumbnailPaths(for: latest) {
                        allowedThumbnailPaths.insert(path)
                    }
                }
            }
        }

        // Also collect all message IDs currently present in snapshot (for virtualization/delete safety)
        let presentMessageIDs: Set<String> = Set(
            items.compactMap { item in
                if case let .message(m) = item { return m.ID }
                return nil
            }
        )

        let thumbnailPathsToCancel = thumbnailPrefetchTasks.keys.filter { path in
            !allowedThumbnailPaths.contains(path)
        }
        for path in thumbnailPathsToCancel {
            cancelThumbnailPrefetchIfNeeded(for: path)
        }

        // Cancel tasks that are either outside allowed window or not present in snapshot anymore
        let idsToCancel = videoPrefetchTasks.keys.filter { id in
            !allowedIDs.contains(id) || !presentMessageIDs.contains(id)
        }
        guard !idsToCancel.isEmpty else { return }

        for id in idsToCancel {
            cancelVideoPrefetchIfNeeded(for: id)
        }
    }

    private func thumbnailPaths(for message: ChatMessage) -> [String] {
        var seen = Set<String>()
        return message.displayableAttachments
            .compactMap { attachment in
                let path = attachment.normalizedThumbPath
                guard !path.isEmpty, seen.insert(path).inserted else { return nil }
                return path
            }
    }

    // Ring-order: start, +1, -1, +2, -2, ...
    private func ringOrderIndices(count: Int, start: Int) -> [Int] {
        guard count > 0 else { return [] }
        let s = max(0, min(start, count - 1))
        var result: [Int] = [s]; var step = 1
        while result.count < count {
            let r = s + step; if r < count { result.append(r) }
            if result.count == count { break }
            let l = s - step; if l >= 0 { result.append(l) }
            step += 1
        }
        return result
    }
    
}

private extension ChatViewController {
    @MainActor
    func setupCustomNavigationBar() {
        self.view.addSubview(customNavigationBar)
        NSLayoutConstraint.activate([
            customNavigationBar.topAnchor.constraint(equalTo: self.view.topAnchor),
            customNavigationBar.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            customNavigationBar.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
        ])
        
        guard let room = self.room else { return }
        customNavigationBar.configureForChatRoom(
            roomTitle: room.roomName,
            participantCount: room.memberCount,
            target: self,
            onBack: #selector(backButtonTapped),
            onSearch: #selector(searchButtonTapped),
            onSetting: #selector(settingButtonTapped)
        )
    }
}

extension ChatViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === chatMessageCollectionView else { return }
        Task { @MainActor in
            self.scheduleMediaPrefetchCleanup(
                delayMs: self.mediaPrefetchCleanupDelayMs,
                pad: self.mediaPrefetchPad
            )
        }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        triggerShakeIfNeeded()
        Task { @MainActor in
            self.scheduleMediaPrefetchCleanup(
                delayMs: self.mediaPrefetchCleanupDelayMs,
                pad: self.mediaPrefetchPad
            )
        }
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        triggerShakeIfNeeded()
        Task { @MainActor in
            self.scheduleMediaPrefetchCleanup(
                delayMs: self.mediaPrefetchCleanupDelayMs,
                pad: self.mediaPrefetchPad
            )
        }
    }
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            triggerShakeIfNeeded()
            Task { @MainActor in
                self.scheduleMediaPrefetchCleanup(
                    delayMs: self.mediaPrefetchCleanupDelayMs,
                    pad: self.mediaPrefetchPad
                )
            }
        }
    }
    
    @MainActor
    private func triggerShakeIfNeeded() {
        guard let indexPath = scrollTargetIndex,
              let cell = chatMessageCollectionView.cellForItem(at: indexPath) as? ChatMessageCell else {
            return
        }
        cell.shakeHorizontally()
        scrollTargetIndex = nil  // 초기화
    }
}

extension ChatViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView,
                        willDisplay cell: UICollectionViewCell,
                        forItemAt indexPath: IndexPath) {
        let itemCount = collectionView.numberOfItems(inSection: 0)
        
        // ✅ Older 메시지 로드
        if indexPath.item < 5, chatRoomViewModel.hasMoreOlder, !chatRoomViewModel.isLoadingOlder {
            if let lastIndex = Self.lastTriggeredOlderIndex,
               abs(lastIndex - indexPath.item) < minTriggerDistance {
                return // 너무 가까운 위치에서 또 호출 → 무시
            }
            Self.lastTriggeredOlderIndex = indexPath.item
            
            let firstID = messageWindowStore.firstMessageID()
            Task {
                await loadOlderMessages(before: firstID)
            }
        }
        
        // ✅ Newer 메시지 로드
        if indexPath.item > itemCount - 5, chatRoomViewModel.hasMoreNewer, !chatRoomViewModel.isLoadingNewer {
            if let lastIndex = Self.lastTriggeredNewerIndex,
               abs(lastIndex - indexPath.item) < minTriggerDistance {
                return
            }
            Self.lastTriggeredNewerIndex = indexPath.item
            
            let lastID = messageWindowStore.lastMessageID()
            Task {
                await loadNewerMessagesIfNeeded(after: lastID)
            }
        }
    }

}

// MARK: - UICollectionViewDataSourcePrefetching for media prefetch
extension ChatViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        guard collectionView === chatMessageCollectionView else { return }
//        guard let roomID = room?.ID, !roomID.isEmpty else { return }

        let roomID = room?.ID ?? ""

        guard !roomID.isEmpty else { return }

        // visible 범위 ± 25로 제한
        let pad = mediaPrefetchPad
        
        let visibleItems = collectionView.indexPathsForVisibleItems
            .filter { $0.section == 0 }
            .map { $0.item }

        let (lowerBound, upperBound): (Int, Int)
        if let minVis = visibleItems.min(), let maxVis = visibleItems.max() {
            lowerBound = max(0, minVis - pad)
            upperBound = maxVis + pad
        } else {
            // If nothing is visible yet, fall back to the incoming prefetch range
            let candidates = indexPaths.filter { $0.section == 0 }.map { $0.item }
            guard let minIdx = candidates.min(), let maxIdx = candidates.max() else { return }
            lowerBound = max(0, minIdx - pad)
            upperBound = maxIdx + pad
        }

        for indexPath in indexPaths where indexPath.section == 0 {
            guard indexPath.item >= lowerBound, indexPath.item <= upperBound else { continue }
            guard let item = dataSource.itemIdentifier(for: indexPath) else { continue }
            guard case let .message(message) = item else { continue }

            // Use latest state if available
            let latest = messageWindowStore.message(for: message.ID) ?? message
            Task { @MainActor in
                self.startMediaPrefetchIfNeeded(for: latest, roomID: roomID)
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        guard collectionView === chatMessageCollectionView else { return }
        guard !indexPaths.isEmpty else { return }
        Task { @MainActor in
            self.scheduleMediaPrefetchCleanup(
                delayMs: self.mediaPrefetchCleanupDelayMs,
                pad: self.mediaPrefetchPad
            )
        }
    }
}


//MARK: seq 업데이트 헬퍼
extension ChatViewController {
    @MainActor
    private func maybeUpdateLastReadSeq(trigger: String, skipNearBottomCheck: Bool = false) {
        guard isUserInCurrentRoom else { return }
        Task {
            do {
                try await self.chatRoomViewModel.persistIncrementalLastReadSeqForCurrentUser(
                    isNearBottom: isNearBottom(),
                    skipNearBottomCheck: skipNearBottomCheck
                )
            } catch {
                print("⚠️ maybeUpdateLastReadSeq(\(trigger)) 실패: \(error)")
            }
        }
    }

    private func flushLastReadSeq(trigger: String) {
        guard let room,
              chatRoomViewModel.isCurrentUserParticipant(in: room) else { return }
        Task {
            do {
                try await self.chatRoomViewModel.persistFinalLastReadSeqForCurrentUser()
            } catch {
                print("⚠️ \(trigger) lastReadSeq flush 실패: \(error)")
            }
        }
    }

    private func bindAppLifecycleForLastRead() {
        guard appLifecycleObservers.isEmpty else { return }

        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            UIApplication.willResignActiveNotification,
            UIApplication.didEnterBackgroundNotification,
            UIApplication.willTerminateNotification
        ]

        for name in names {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.flushLastReadSeq(trigger: name.rawValue)
            }
            appLifecycleObservers.append(observer)
        }
    }
}
