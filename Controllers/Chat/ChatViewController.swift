//
//  ChatViewController.swift
//  OutPick
//
//  Created by 김가윤 on 10/14/24.
//

import Foundation
import AVFoundation
import UIKit
import AVKit
import Combine
import PhotosUI
import Firebase
import Kingfisher

protocol ChatMessageCellDelegate: AnyObject {
    func cellDidLongPress(_ cell: ChatMessageCell)
}

class ChatViewController: UIViewController, UINavigationControllerDelegate, ChatModalAnimatable {

    // Paging buffer size for scroll triggers
    private var pagingBuffer = 200

    private var isInitialLoading = true

    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var sideMenuBtn: UIBarButtonItem!
    @IBOutlet weak var joinRoomBtn: UIButton!
    
    var swipeRecognizer: UISwipeGestureRecognizer!
    
    private var chatMessageCollectionView = ChatMessageCollectionView()
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private var cancellables = Set<AnyCancellable>()
    private var chatCustomMemucancellables = Set<AnyCancellable>()
    
    private var lastMessageDate: Date?
    private var lastReadMessageID: String?
    
    private var isUserInCurrentRoom = false

    private var replyMessage: ReplyPreview?
    private var messageMap: [String: ChatMessage] = [:]

    // Loading state flags for message paging
    private var isLoadingOlder = false
    private var isLoadingNewer = false
    
    private var hasMoreOlder = true
    private var hasMoreNewer = true
    
    enum Section: Hashable {
        case main
    }
    
    enum Item: Hashable {
        case message(ChatMessage)
        case dateSeparator(Date)
        case readMarker
    }
    
    enum MessageUpdateType {
        case older
        case newer
        case reload
        case initial
    }
    
    var room: ChatRoom?
    var roomID: String?
    var isRoomSaving: Bool = false
    
    var convertImagesTask: Task<Void, Error>? = nil
    var convertVideosTask: Task<Void, Error>? = nil
    
    private var filteredMessages: [ChatMessage] = []
    private var currentFilteredMessageIndex: Int?
    private var highlightedMessageIDs: Set<String> = []
    private var currentSearchKeyword: String? = nil
    private var hasBoundRoomChange = false
    
    static var currentRoomID: String? = nil
    
    // 중복 호출 방지를 위한 최근 트리거 인덱스
    private var minTriggerDistance: Int { return 3 }
    private static var lastTriggeredOlderIndex: Int?
    private static var lastTriggeredNewerIndex: Int?
    
    private var deletionListener: ListenerRegistration?
    
    deinit {
        print("💧 ChatViewController deinit")
        convertImagesTask?.cancel()
        convertVideosTask?.cancel()
        
        deletionListener?.remove()
        deletionListener = nil
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
        
        return view
    }()
    
    private lazy var chatCustomMenu: ChatCustomPopUpMenu = {
        let view = ChatCustomPopUpMenu()
        view.backgroundColor = .black
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
    
    private var settingPanelVC: ChatRoomSettingCollectionView?
    private lazy var dimView: UIView = {
//        let v = UIControl(frame: .zero)
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = UIColor.black.withAlphaComponent(0.35)
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

    override func viewDidLoad() {
        super.viewDidLoad()
        self.definesPresentationContext = true
        
        configureDataSource()
    
        setUpNotifications()
        
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
        decideJoinUI()
        setupAttachmentView()
        
        setupInitialMessages()

        bindKeyboardPublisher()
        bindSearchEvents()
        
        chatMessageCollectionView.delegate = self
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard let room = self.room else { return }
        FirebaseManager.shared.stopListenRoomDoc(roomID: room.ID ?? "")
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isUserInCurrentRoom = false

        if let room = self.room {
            SocketIOManager.shared.unsubscribeFromMessages(for: room.ID ?? "")
            
            if ChatViewController.currentRoomID == room.ID {
                ChatViewController.currentRoomID = nil    // ✅ 나갈 때 초기화
            }
        }
        
        cancellables.removeAll()
        NotificationCenter.default.removeObserver(self)
        
        convertImagesTask?.cancel()
        convertVideosTask?.cancel()
        
        deletionListener?.remove()
        deletionListener = nil
        
        removeReadMarkerIfNeeded()
        
        // 참여하지 않은 방이면 로컬 메시지 삭제 처리
        if let room = self.room,
           !room.participants.contains(LoginManager.shared.getUserEmail) {
            Task { @MainActor in
                do {
                    try GRDBManager.shared.deleteMessages(inRoom: room.ID ?? "")
                    try GRDBManager.shared.deleteImages(inRoom: room.ID ?? "")
                    print("참여하지 않은 사용자의 임시 메시지/이미지 삭제 완료")
                } catch {
                    print("GRDB 메시지/이미지 삭제 실패: \(error)")
                }
            }
        }
        
        self.navigationController?.setNavigationBarHidden(false, animated: false)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.attachInteractiveDismissGesture()
         
        if let room = self.room {
            ChatViewController.currentRoomID = room.ID
        } // ✅ 현재 방 ID 저장
//        bindMessagePublishers()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.notiView.layer.cornerRadius = 15
    }
    
    //MARK: 메시지 관련
    @MainActor
    private func setupInitialMessages() {
        Task {
            LoadingIndicator.shared.start(on: self)
            defer { LoadingIndicator.shared.stop() }
            
            guard let room = self.room else { return }
            guard room.participants.contains(LoginManager.shared.getUserEmail) else { return }
            
            do {
                // 1. GRDB 로드
                let localMessages = try await GRDBManager.shared.fetchRecentMessages(inRoom: room.ID ?? "", limit: 200)
                addMessages(localMessages, updateType: .initial)
                self.lastReadMessageID = localMessages.last?.ID
                
                // 2. 삭제 상태 동기화
                await syncDeletedStates(localMessages: localMessages, room: room)
                
                // 3. Firebase 전체 메시지 로드
                let serverMessages = try await FirebaseManager.shared.fetchMessagesPaged(for: room, pageSize: 300, reset: true)
                try await GRDBManager.shared.saveChatMessages(serverMessages)
                addMessages(serverMessages, updateType: .newer)
                
                isUserInCurrentRoom = true
                bindMessagePublishers()
            } catch {
                print("❌ 메시지 초기화 실패:", error)
            }
            isInitialLoading = false
        }
    }
    
    @MainActor
    private func syncDeletedStates(localMessages: [ChatMessage], room: ChatRoom) async {
        do {
            // 1) 로컬 200개 메시지의 ID / 삭제상태 맵
            let localIDs = localMessages.map { $0.ID }
            let localDeletionStates = Dictionary(uniqueKeysWithValues: localMessages.map { ($0.ID, $0.isDeleted) })

            // 2) 서버에서 해당 ID들의 삭제 상태만 조회 (chunked IN query)
            let serverMap = try await FirebaseManager.shared.fetchDeletionStates(roomID: room.ID ?? "", messageIDs: localIDs)

            // 3) 서버가 true인데 로컬은 false인 ID만 업데이트 대상
            let idsToUpdate: [String] = localIDs.filter { (serverMap[$0] ?? false) && ((localDeletionStates[$0] ?? false) == false) }
            guard !idsToUpdate.isEmpty else { return }

            let roomID = room.ID ?? ""

            // 4) GRDB 영속화: 원본 isDeleted + 해당 원본을 참조하는 replyPreview.isDeleted
            try await GRDBManager.shared.updateMessagesIsDeleted(idsToUpdate, isDeleted: true, inRoom: roomID)
            try await GRDBManager.shared.updateReplyPreviewsIsDeleted(referencing: idsToUpdate, isDeleted: true, inRoom: roomID)

            // 5) UI 배치 리로드 셋업
            //    - 원본: isDeleted=true로 마킹된 복사본
            let deletedMessages: [ChatMessage] = localMessages
                .filter { idsToUpdate.contains($0.ID) }
                .map { msg in var copy = msg; copy.isDeleted = true; return copy }

            //    - 답장: replyPreview.messageID ∈ idsToUpdate → replyPreview.isDeleted=true 복사본
            let affectedReplies: [ChatMessage] = localMessages
                .filter { msg in (msg.replyPreview?.messageID).map(idsToUpdate.contains) ?? false }
                .map { reply in var copy = reply; copy.replyPreview?.isDeleted = true; return copy }

            let toReload = deletedMessages + affectedReplies
            if !toReload.isEmpty {
                addMessages(toReload, updateType: .reload)
            }
        } catch {
            print("❌ 삭제 상태 동기화 실패:", error)
        }
    }

    @MainActor
    private func removeReadMarkerIfNeeded() {
        var snapshot = dataSource.snapshot()
        if let marker = snapshot.itemIdentifiers.first(where: {
            if case .readMarker = $0 { return true }
            return false
        }) {
            snapshot.deleteItems([marker])
            dataSource.apply(snapshot, animatingDifferences: false)
        }
    }
    
    @MainActor
    private func loadOlderMessages(before messageID: String?) async {
        // Note: willDisplay cell logic already handles trigger conditions (scroll position, etc.)
        guard !isLoadingOlder, hasMoreOlder else { return }
        guard let room = self.room else { return }
        
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        
        print(#function, "✅ loading older 진행")
        do {
            // 1. GRDB에서 먼저 최대 100개
            let local = try await GRDBManager.shared.fetchOlderMessages(
                inRoom: room.ID ?? "",
                before: messageID ?? "",
                limit: 100
            )
            var loadedMessages = local
            
            // 2. 부족분은 서버에서 채우기
            if local.count < 100 {
                let needed = 100 - local.count
                let server = try await FirebaseManager.shared.fetchOlderMessages(
                    for: room,
                    before: messageID ?? "",
                    limit: needed
                )
                
                if server.isEmpty {
                    hasMoreOlder = false   // 더 이상 이전 메시지 없음
                } else {
                    try await GRDBManager.shared.saveChatMessages(server)
                    loadedMessages.append(contentsOf: server)
                }
            }
            
            if loadedMessages.isEmpty {
                hasMoreOlder = false
            } else {
                // Chunk messages into groups of 20 for performance
                let chunkSize = 20
                let total = loadedMessages.count
                for i in stride(from: 0, to: total, by: chunkSize) {
                    let end = min(i + chunkSize, total)
                    let chunk = Array(loadedMessages[i..<end])
                    addMessages(chunk, updateType: .older)
                }
            }
        } catch {
            print("❌ loadOlderMessages 실패:", error)
        }
    }

    @MainActor
    private func loadNewerMessagesIfNeeded(after messageID: String?) async {
        // In real-time subscription mode, hasMoreNewer is not needed except when explicitly doing a server fetch.
        // Only guard against isLoadingNewer to allow real-time updates to always flow.
        guard !isLoadingNewer else { return }
        guard let room = self.room else { return }

        isLoadingNewer = true
        defer { isLoadingNewer = false }

        print(#function, "✅ loading newer 진행")
        do {
            // 1. 서버에서 lastMessageID 이후 메시지 보충 (최대 100개)
            let server = try await FirebaseManager.shared.fetchMessagesAfter(
                room: room,
                after: messageID ?? "",
                limit: 100
            )

            // If server returns empty, simply exit; do not modify any flags.
            if server.isEmpty {
                // No new messages from server; do nothing.
                return
            } else {
                try await GRDBManager.shared.saveChatMessages(server)
                // Chunk messages into groups of 20 for performance
                let chunkSize = 20
                let total = server.count
                for i in stride(from: 0, to: total, by: chunkSize) {
                    let end = min(i + chunkSize, total)
                    let chunk = Array(server[i..<end])
                    addMessages(chunk, updateType: .newer)
                }
            }
        } catch {
            print("❌ loadNewerMessagesIfNeeded 실패:", error)
        }
    }

    private func bindMessagePublishers() {
        guard let room = self.room else { return }
        SocketIOManager.shared.subscribeToMessages(for: room.ID ?? "")
            .sink { [weak self] receivedMessage in
                guard let self = self else { return }
                Task {
                    await self.handleIncomingMessage(receivedMessage)
                }
            }
            .store(in: &cancellables)
        
        deletionListener = FirebaseManager.shared.listenToDeletedMessages(roomID: room.ID ?? "") { [weak self] deletedMessageID in
            guard let self = self else { return }
            Task { @MainActor in
                let roomID = room.ID ?? ""

                // 1) GRDB 영속화: 원본 + 답장 preview
                do {
                    try await GRDBManager.shared.updateMessagesIsDeleted([deletedMessageID], isDeleted: true, inRoom: roomID)
                    try await GRDBManager.shared.updateReplyPreviewsIsDeleted(referencing: [deletedMessageID], isDeleted: true, inRoom: roomID)
                } catch {
                    print("❌ GRDB deletion persistence failed:", error)
                }

                // 2) messageMap 최신화 및 배치 리로드 목록 구성
                var toReload: [ChatMessage] = []

                if var deletedMsg = self.messageMap[deletedMessageID] {
                    deletedMsg.isDeleted = true
                    self.messageMap[deletedMessageID] = deletedMsg
                    toReload.append(deletedMsg)
                } else {
                    print("⚠️ deleted message not in window: \(deletedMessageID)")
                }

                let repliesInWindow = self.messageMap.values.filter { $0.replyPreview?.messageID == deletedMessageID }
                for var reply in repliesInWindow {
                    reply.replyPreview?.isDeleted = true
                    self.messageMap[reply.ID] = reply
                    toReload.append(reply)
                }

                // 3) UI 반영 (한 번만)
                if !toReload.isEmpty {
                    self.addMessages(toReload, updateType: .reload)
                }
            }
        }
    }
    
    /// 수신 메시지를 저장 및 UI 반영
    @MainActor
    private func handleIncomingMessage(_ message: ChatMessage) async {
        guard let room = self.room else { return }
        
        print("\(message.isFailed ? "전송 실패" : "전송 성공") 메시지 수신: \(message)")
        
        do {
            if !message.isFailed, message.senderID == LoginManager.shared.getUserEmail {
                try await FirebaseManager.shared.saveMessage(message, room)
            }
            try await GRDBManager.shared.saveChatMessages([message])
            
            if !message.attachments.isEmpty {
                await cacheAttachmentsIfNeeded(for: message, in: room.ID ?? "")
            }
            
            addMessages([message], updateType: .newer)
        } catch {
            print("❌ 메시지 처리 실패: \(error)")
        }
    }
    
    /// 첨부파일 캐싱 전용
    private func cacheAttachmentsIfNeeded(for message: ChatMessage, in roomID: String) async {
        guard !message.attachments.isEmpty else { return }
        
        for attachment in message.attachments {
            guard attachment.type == .image, let imageName = attachment.fileName else { continue }
            
            do {
                if !message.isFailed {
                    try GRDBManager.shared.addImage(imageName, toRoom: roomID, at: message.sentAt ?? Date())
                }
                if let image = attachment.toUIImage() {
                    try await KingfisherManager.shared.cache.store(image, forKey: imageName)
                }
            } catch {
                print("❌ 첨부파일 캐싱 실패: \(error)")
            }
        }
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
        
        chatUIViewBottomConstraint = chatUIView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        NSLayoutConstraint.activate([
            chatUIView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chatUIView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chatUIViewBottomConstraint!,
            chatUIView.heightAnchor.constraint(greaterThanOrEqualToConstant: chatUIView.minHeight),
            
            chatMessageCollectionView.heightAnchor.constraint(equalTo: view.heightAnchor),
            chatMessageCollectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chatMessageCollectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chatMessageCollectionView.bottomAnchor.constraint(equalTo: chatUIView.topAnchor),
        ])
        
        view.bringSubviewToFront(chatUIView)
        view.bringSubviewToFront(customNavigationBar)
        chatMessageCollectionView.contentInset.top = self.view.safeAreaInsets.top + chatUIView.frame.height + 5
        chatMessageCollectionView.contentInset.bottom = 5
        
        NSLayoutConstraint.deactivate(joinConsraints)
        setupCopyReplyDeleteView()
    }
    
    @MainActor
    private func handleSendButtonTap() {
        guard let message = self.chatUIView.messageTextView.text,
              !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let room = self.room else { return }

            self.chatUIView.messageTextView.text = nil
            self.chatUIView.updateHeight()
            self.chatUIView.sendButton.isEnabled = false
        
        let newMessage = ChatMessage(ID: UUID().uuidString, roomID: room.ID ?? "", senderID: LoginManager.shared.getUserEmail, senderNickname: LoginManager.shared.currentUserProfile?.nickname ?? "", msg: message, sentAt: Date(), attachments: [], replyPreview: replyMessage)

        Task.detached {
            SocketIOManager.shared.sendMessages(room, newMessage)
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
    
    private func playVideo(from url: URL) {
        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        let playerViewController = AVPlayerViewController()
        playerViewController.player = player
        
        present(playerViewController, animated: true) {
            player.play()
        }
    }
    
    private func openCamera() {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            let imagePicker = UIImagePickerController()
            imagePicker.delegate = self
            imagePicker.allowsEditing = true
            imagePicker.sourceType = .camera
            
            present(imagePicker, animated: true, completion: nil)
        }
    }
    
    private func openPHPicker() {
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
    private func setUpNotifications() {
        // 방 저장 관련
        NotificationCenter.default.addObserver(self, selector: #selector(handleRoomSaveCompleted), name: .roomSavedComplete, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRoomSaveFailed), name: .roomSaveFailed, object: nil)
    }
    
    @MainActor
    private func bindRoomChangePublisher() {
        if hasBoundRoomChange { return }
        hasBoundRoomChange = true
        
        // 실시간 방 업데이트 관련
        FirebaseManager.shared.roomChangePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] updatedRoom in
                guard let self = self else { return }
                let previousRoom = self.room
                self.room = updatedRoom
                print(#function, "ChatViewController.swift 방 정보 변경: \(updatedRoom)")
                Task { @MainActor in
                    await self.applyRoomDiffs(old: previousRoom, new: updatedRoom)
                }
            }
            .store(in: &cancellables)
    }

    /// 방 정보(old → new) 변경점을 비교하고 필요한 UI/동기화만 수행
    @MainActor
    private func applyRoomDiffs(old: ChatRoom?, new: ChatRoom) async {
        // 최초 바인딩 또는 이전 정보가 없을 때: 전체 초기화 느낌으로 처리
        guard let old = old else {
            updateNavigationTitle(with: new)
            do { try await syncProfilesWithLocalDB(emails: new.participants) } catch { print("❌ 프로필 동기화 실패: \(error)") }
            setupAnnouncementBannerIfNeeded()
            updateAnnouncementBanner(with: new.activeAnnouncement)
            return
        }

        // 1) 타이틀/참여자 수 변경 시 상단 네비바만 갱신
        if old.roomName != new.roomName || old.participants.count != new.participants.count {
            updateNavigationTitle(with: new)
        }

        // 2) 참여자 변경 시, 새로 추가된 사용자만 동기화(최소화)
        let oldSet = Set(old.participants)
        let newSet = Set(new.participants)
        let joined = Array(newSet.subtracting(oldSet))
        if !joined.isEmpty {
            do { try await syncProfilesWithLocalDB(emails: joined) } catch { print("❌ 프로필 부분 동기화 실패: \(error)") }
        }

        // 3) 공지 변경 감지: ID/업데이트 시각/본문/작성자 중 하나라도 달라지면 배너 갱신
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
    
    @objc private func handleRoomSaveCompleted(notification: Notification) {
        guard let savedRoom = notification.userInfo?["room"] as? ChatRoom else { return }
        self.room = savedRoom
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updateNavigationTitle(with: savedRoom)
            LoadingIndicator.shared.stop()
            self.view.isUserInteractionEnabled = true
            
            // 이미 연결된 경우에는 room 생성과 join만 수행
            if SocketIOManager.shared.isConnected {
                SocketIOManager.shared.createRoom(savedRoom.roomName)
                SocketIOManager.shared.joinRoom(savedRoom.roomName)
            }
        }
    }
    
    @objc private func handleRoomSaveFailed(notification: Notification) {
        activityIndicator.stopAnimating()
        
        guard let error = notification.userInfo?["error"] as? RoomCreationError else { return }
        showAlert(error: error)
    }
    
    //MARK: 프로필 관련
    @MainActor
    private func syncProfilesWithLocalDB(emails: [String]) async throws {
        print(#function, "호출 완료")
        
        do {
            let profiles = try await FirebaseManager.shared.fetchUserProfiles(emails: emails)
            
            guard let room = self.room else { return }
            for profile in profiles {
                try GRDBManager.shared.insertUserProfile(profile)
                try GRDBManager.shared.addUser(profile.email ?? "", toRoom: room.ID ?? "")
            }
            
            print(#function, "✅ 사용자 프로필 동기화 성공: ", profiles)
        } catch {
            print("❌ 사용자 프로필 동기화 실패: \(error)")
        }
    }
    

    // MARK: 초기 UI 설정 관련
    @MainActor
    private func decideJoinUI() {
        guard let room = room else { return }
        
        Task {
            if room.participants.contains(LoginManager.shared.getUserEmail) {
                setupChatUI()
                chatUIView.isHidden = false
                joinRoomBtn.isHidden = true
                try await self.syncProfilesWithLocalDB(emails: room.participants)
                self.bindRoomChangePublisher()
                FirebaseManager.shared.startListenRoomDoc(roomID: room.ID ?? "")
                self.setupAnnouncementBannerIfNeeded()
                self.updateAnnouncementBanner(with: room.activeAnnouncement)
            } else {
                setJoinRoombtn()
                joinRoomBtn.isHidden = false
                chatUIView.isHidden = true
                self.customNavigationBar.rightStack.isUserInteractionEnabled = false
            }
            
            updateNavigationTitle(with: room)
        }
    }
    
    private func setJoinRoombtn() {
        self.joinRoomBtn.clipsToBounds = true
        self.joinRoomBtn.layer.cornerRadius = 20
        self.joinRoomBtn.backgroundColor = UIColor(white: 0.1, alpha: 0.05)
        joinRoomBtn.translatesAutoresizingMaskIntoConstraints = false
        
        if chatMessageCollectionView.superview == nil {
            view.addSubview(chatMessageCollectionView)
            chatMessageCollectionView.translatesAutoresizingMaskIntoConstraints = false
            
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
    @IBAction func joinRoomBtnTapped(_ sender: UIButton) {
        guard let room = self.room else { return }
        
        joinRoomBtn.isHidden = true
        customNavigationBar.rightStack.isUserInteractionEnabled = true
        
        NSLayoutConstraint.deactivate(joinConsraints)
        joinConsraints.removeAll()
        if chatMessageCollectionView.superview != nil {
            chatMessageCollectionView.removeFromSuperview()
        }
        
        Task {
            do {
                // 1. 소켓 연결 (async/await 버전)
                if !SocketIOManager.shared.isConnected {
                    try await SocketIOManager.shared.establishConnection()
                    SocketIOManager.shared.joinRoom(room.ID ?? "")
                    SocketIOManager.shared.listenToNewParticipant()
                }
                
                // 2. Firebase에 참여자 등록
                try await FirebaseManager.shared.add_room_participant(room: room)
                
                // 3. 최신 room 정보 fetch
                let updatedRoom = try await FirebaseManager.shared.fetchRoomInfo(room: room)
                self.room = updatedRoom
                
                // 4. 프로필 동기화
//                try await self.syncProfilesWithLocalDB(emails: updatedRoom.participants)
                
                // 5. UI 업데이트
                await MainActor.run {
                    self.setupChatUI()
                    self.chatUIView.isHidden = false
                    self.chatMessageCollectionView.isHidden = false
                    self.bindRoomChangePublisher()
                    FirebaseManager.shared.startListenRoomDoc(roomID: updatedRoom.ID ?? "")
                    self.view.layoutIfNeeded()
                }
                
                print(#function, "✅ 방 참여 성공, UI 업데이트 완료")
                
            } catch {
                print("❌ 방 참여 처리 실패: \(error)")
                await MainActor.run {
                    self.joinRoomBtn.isHidden = false
                    self.customNavigationBar.rightStack.isUserInteractionEnabled = false
                }
            }
        }
    }
    
    //MARK: 커스텀 내비게이션 바
    @MainActor
    @objc private func backButtonTapped() {
        
        let transition = CATransition()
        transition.duration = 0.3
        transition.type = .push
        transition.subtype = .fromLeft // 왼쪽에서 오른쪽으로 이동 (pop 느낌)
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        
        self.view.window?.layer.add(transition, forKey: kCATransition)
        
        if isRoomSaving {
            if let previous = self.presentingViewController {
                if previous is RoomCreateViewController {
                    let storyboard = UIStoryboard(name: "Main", bundle: nil)
                    let chatListVC = storyboard.instantiateViewController(withIdentifier: "chatListVC")
                    chatListVC.modalPresentationStyle = .fullScreen
                    self.present(chatListVC, animated: false)
                }
            }
        }
        else {
            // 일반적인 경우 이전 화면으로 이동
            //            ChatModalTransitionManager.dismiss(from: self)
            self.dismiss(animated: true)
        }
    }
    
    @objc private func settingButtonTapped() {
        Task { @MainActor in
            guard let room = self.room else { return }
            let profiles = try GRDBManager.shared.fetchUserProfiles(inRoom: room.ID ?? "")
            
            var images = [UIImage]()
            let imageNames = try GRDBManager.shared.fetchImageNames(inRoom: room.ID ?? "")
            for imageName in imageNames {
                if let image = await KingFisherCacheManager.shared.loadImage(named: imageName) {
                    images.append(image)
                }
            }

            self.detachInteractiveDismissGesture()
            
            let settingVC = ChatRoomSettingCollectionView(room: room, profiles: profiles, images: images)
            self.presentSettingVC(settingVC)
            
            settingVC.onRoomUpdated = { [weak self] updatedRoom in
                guard let self = self else { return }
                Task { @MainActor in
                    let old = self.room
                    self.room = updatedRoom
                    await self.applyRoomDiffs(old: old, new: updatedRoom)
                }
            }
        }
    }
    
    @MainActor
    private func presentSettingVC(_ VC: ChatRoomSettingCollectionView) {
        guard settingPanelVC == nil else { return }
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
        dismissSettingVC()
    }
    
    @MainActor
    private func dismissSettingVC() {
        guard let VC = settingPanelVC else { return }
        
        print(#function, "호출")
        
        VC.willMove(toParent: nil)
        UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseIn]) {
            self.dimView.alpha = 0
            VC.view.frame.origin.x = self.view.bounds.width
        } completion: { _ in
            VC.view.removeFromSuperview()
            VC.removeFromParent()
            self.settingPanelVC = nil
        }
        
        self.attachInteractiveDismissGesture()
    }

    @MainActor
    private func updateNavigationTitle(with room: ChatRoom) {
        // ✅ 커스텀 내비게이션 바 타이틀 업데이트
        customNavigationBar.configureForChatRoom(
            roomTitle: room.roomName,
            participantCount: room.participants.count,
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
                
                self.clearPreviousHighlightIfNeeded()
                
                guard let keyword = keyword, !keyword.isEmpty else {
                    print(#function, "✅✅✅✅✅ keyword is empty ✅✅✅✅✅")
                    return
                }
                filterMessages(containing: keyword)
            }
            .store(in: &cancellables)
        
        customNavigationBar.cancelSearchPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self = self else { return }
                self.exitSearchMode()
            }
            .store(in: &cancellables)
        
        searchUI.upPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self = self else { return }
                currentFilteredMessageIndex! -= 1
                searchUI.updateSearchResult(filteredMessages.count, currentFilteredMessageIndex!)
                moveToMessageAndShake(currentFilteredMessageIndex!)
            }
            .store(in: &cancellables)
        
        searchUI.downPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self = self else { return }
                currentFilteredMessageIndex! += 1
                searchUI.updateSearchResult(filteredMessages.count, currentFilteredMessageIndex!)
                moveToMessageAndShake(currentFilteredMessageIndex!)
            }
            .store(in: &cancellables)
    }
    
    @MainActor
    private func filterMessages(containing keyword: String) {
        Task {
            do {
                guard let room = self.room else { return }
                
                filteredMessages = try await GRDBManager.shared.fetchMessages(in: room.ID ?? "", containing: keyword)
                currentFilteredMessageIndex = filteredMessages.isEmpty == true ? nil : filteredMessages.count
                currentSearchKeyword = keyword
                highlightedMessageIDs = Set(filteredMessages.map { $0.ID })
                applyHighlight()
                
            } catch {
                print("메시지 없음")
            }
        }
    }
    
    @MainActor
    private func moveToMessageAndShake(_ idx: Int) {
        let message = filteredMessages[idx-1]
        guard let indexPath = indexPath(of: message) else { return }
        
        if let cell = chatMessageCollectionView.cellForItem(at: indexPath) as? ChatMessageCell {
            cell.shakeHorizontally()
        } else {
            chatMessageCollectionView.scrollToMessage(at: indexPath)
            scrollTargetIndex = indexPath
        }
    }
    
    @MainActor
    private func applyHighlight() {
        var snapshot = dataSource.snapshot()
        
        let itemsToRealod = snapshot.itemIdentifiers.compactMap { item -> Item? in
            if case let .message(message) = item, highlightedMessageIDs.contains(message.ID){
                return .message(message)
            }
            return nil
        }
        
        if !itemsToRealod.isEmpty {
            snapshot.reloadItems(itemsToRealod)
            dataSource.apply(snapshot, animatingDifferences: false)
        }
        
        searchUI.updateSearchResult(highlightedMessageIDs.count, currentFilteredMessageIndex ?? 0)
        if let idx = currentFilteredMessageIndex { moveToMessageAndShake(idx) }
    }
    
    @MainActor
    private func clearPreviousHighlightIfNeeded() {
        var snapshot = dataSource.snapshot()
        
        let itemsToRealod = snapshot.itemIdentifiers.compactMap { item -> Item? in
            if case let .message(message) = item, highlightedMessageIDs.contains(message.ID){
                return .message(message)
            }
            return nil
        }
        
        highlightedMessageIDs.removeAll()
        currentSearchKeyword = nil
        scrollTargetIndex = nil
        
        if !itemsToRealod.isEmpty {
            snapshot.reloadItems(itemsToRealod)
            dataSource.apply(snapshot, animatingDifferences: false)
        }
        
        searchUI.updateSearchResult(highlightedMessageIDs.count, currentFilteredMessageIndex ?? 0)
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
        customNavigationBar.switchToSearchMode()
        setupSearchUI()
        
        searchUI.isHidden = false
        chatUIView.isHidden = true
    }
    
    private func indexPath(of message: ChatMessage) -> IndexPath? {
        let snapshot = dataSource.snapshot()
        let items = snapshot.itemIdentifiers(inSection: .main)
        if let row = items.firstIndex(where: { $0 == .message(message) }) {
            return IndexPath(item: row, section: 0)
        } else {
            return nil
        }
    }

    //MARK: 메시지 삭제/답장/복사 관련
    @MainActor
    private func showCustomMenu(at indexPath: IndexPath/*, aboveCell: Bool*/) {
        guard let cell = chatMessageCollectionView.cellForItem(at: indexPath) as? ChatMessageCell,
              let item = dataSource.itemIdentifier(for: indexPath),
              case let .message(message) = item,
              message.isDeleted == false else { return }
        
        // 1.셀 강조하기
        cell.setHightlightedOverlay(true)
        highlightedCell = cell
        
        // 셀의 bounds 기준으로 컬렉션뷰 내 프레임 계산
        let cellFrameInCollection = cell.convert(cell.bounds, to: chatMessageCollectionView/*.collectionView*/)
        let cellCenterY = cellFrameInCollection.midY
        
        // 컬렉션 뷰 기준 중앙 사용 (화면 절반)
        let screenMiddleY = chatMessageCollectionView.bounds.midY
        let showAbove: Bool = cellCenterY > screenMiddleY
        
        // 신고 or 삭제 결정
        if let userProfile = LoginManager.shared.currentUserProfile,
           let room = self.room {
            let isOwner = userProfile.nickname == message.senderNickname
            let isAdmin = room.creatorID == userProfile.email
            
            chatCustomMenu.configurePermissions(canDelete: isOwner || isAdmin, canAnnounce: isAdmin)
        }
        
        // 2.메뉴 위치를 셀 기준으로
        view.addSubview(chatCustomMenu)
        NSLayoutConstraint.activate([
            showAbove ? chatCustomMenu.bottomAnchor.constraint(equalTo: cell.referenceView.topAnchor, constant: -8) : chatCustomMenu.topAnchor.constraint(equalTo: cell.referenceView.bottomAnchor, constant: 8),
            
            LoginManager.shared.userProfile?.nickname == message.senderNickname ? chatCustomMenu.trailingAnchor.constraint(equalTo: cell.referenceView.trailingAnchor, constant: 0) : chatCustomMenu.leadingAnchor.constraint(equalTo: cell.referenceView.leadingAnchor, constant: 0)
        ])
        
        // 3. 버튼 액션 설정
        setChatMenuActions(for: message)
    }
    
    private func setChatMenuActions(for message: ChatMessage) {
        chatCustomMenu.onReply = { [weak self] in
            guard let self = self else { return }
            self.handleReply(message: message)
            self.dismissCustomMenu()
        }
        
        chatCustomMenu.onCopy = { [weak self] in
            guard let self = self else { return }
            self.handleCopy(message: message)
            self.dismissCustomMenu()
        }
        
        chatCustomMenu.onDelete = { [weak self] in
            guard let self = self else { return }
            ConfirmView.present(in: self.view,
                                      message: "삭제 시 모든 사용자의 채팅창에서 메시지가 삭제되며\n‘삭제된 메시지입니다.’로 표기됩니다.",
                                      onConfirm: { [weak self] in
                guard let self = self else { return }
                self.handleDelete(message: message)
            })
            self.dismissCustomMenu()
        }
        
        chatCustomMenu.onReport = { [weak self] in
            self?.handleReport(message: message)
            self?.dismissCustomMenu()
        }
        
        chatCustomMenu.onAnnounce = { [weak self] in
            guard let self = self else { return }
            print(#function, "공지:", message.msg ?? "")
            
            ConfirmView.presentAnnouncement(in: self.view, onConfirm: { [weak self] in
                guard let self = self else { return }
                self.handleAnnouncement(message)
            })
            
            self.dismissCustomMenu()
        }
    }
    
    private func handleAnnouncement(_ message: ChatMessage) {
        let announcement = AnnouncementPayload(text: message.msg ?? "", authorID: LoginManager.shared.currentUserProfile?.nickname ?? "", createdAt: Date())
        Task { @MainActor in
            guard let room = self.room else { return }
            try await FirebaseManager.shared.setActiveAnnouncement(roomID: room.ID ?? "", messageID: message.ID, payload: announcement)
            showSuccess("공지를 등록했습니다.")
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
        self.replyMessage = ReplyPreview(messageID: message.ID, sender: message.senderNickname, text: message.msg ?? "", isDeleted: false)
        replyView.configure(with: message)
        replyView.isHidden = false
    }
    
    private func handleCopy(message: ChatMessage) {
        UIPasteboard.general.string = message.msg
        print(#function, "복사:", message)
        // 필요 시 UI 피드백
        showSuccess("메시지가 복사되었습니다.")
    }
    
    private func handleDelete(message: ChatMessage) {
        Task {
            guard let room = self.room else { return }
            let messageID = message.ID
            do {
                // 1. GRDB 업데이트
                try await GRDBManager.shared.updateMessagesIsDeleted([messageID], isDeleted: true, inRoom: room.ID ?? "")

                // 2. Firestore 업데이트
                do {
                    try await FirebaseManager.shared.updateMessageIsDeleted(roomID: room.ID ?? "", messageID: messageID)
                    print("✅ 메시지 삭제 성공: \(messageID)")
                } catch {
                    print("❌ 메시지 Firestore 삭제 처리 실패:", error)
                }
            } catch {
                print("❌ 메시지 삭제 처리 실패:", error)
            }
        }
    }
    
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let location = gesture.location(in: chatMessageCollectionView)
        if let indexPath = chatMessageCollectionView.indexPathForItem(at: location) {
            showCustomMenu(at: indexPath)
        }
    }

    @objc private func handleAnnouncementBannerLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let room = self.room,
              room.creatorID == LoginManager.shared.getUserEmail else { return }
        
        // 확인 팝업 → 삭제 실행
        ConfirmView.present(
            in: self.view,
            message: "현재 공지를 삭제할까요?\n삭제 시 모든 사용자의 배너에서 사라집니다.",
            style: .prominent,
            onConfirm: { [weak self] in
                guard let self = self else { return }
                Task { @MainActor in
                    do {
                        try await FirebaseManager.shared.clearActiveAnnouncement(roomID: room.ID ?? "")
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
        chatCustomMenu.removeFromSuperview()
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
    
    private func isCurrentUser(_ email: String?) -> Bool {
        return (email ?? "") == LoginManager.shared.getUserEmail
    }
    private func isCurrentUserAdmin(of room: ChatRoom) -> Bool {
        return room.creatorID == LoginManager.shared.getUserEmail
    }

    //MARK: Diffable Data Source
    private func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: chatMessageCollectionView) { [weak self] collectionView, indexPath, item in
            guard let self = self else { return  nil }
            
            switch item {
            case .message(let message):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ChatMessageCell.reuseIdentifier, for: indexPath) as! ChatMessageCell

                // ✅ Always prefer the latest state from messageMap
                let latestMessage = self.messageMap[message.ID] ?? message

                if latestMessage.attachments.isEmpty {
                    cell.configureWithMessage(with: latestMessage)
                } else {
                    cell.configureWithImage(with: latestMessage)
                }

                let keyword = self.highlightedMessageIDs.contains(latestMessage.ID) ? self.currentSearchKeyword : nil
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
        applySnapshot([])
    }
    
    func applySnapshot(_ items: [Item]) {
        var snapshot = dataSource.snapshot()
        if snapshot.sectionIdentifiers.isEmpty { snapshot.appendSections([Section.main]) }
        snapshot.appendItems(items, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: false)
        chatMessageCollectionView.scrollToBottom()
    }

    @MainActor
    func addMessages(_ messages: [ChatMessage], updateType: MessageUpdateType = .initial) {
        let windowSize = 300
        var snapshot = dataSource.snapshot()
        
        if updateType == .reload {
            reloadDeletedMessages(messages)
            return
        }
        
        let existingIDs = snapshot.itemIdentifiers.compactMap { if case .message(let m) = $0 { return m.ID } else { return nil } }
        let newMessages = messages.filter { !existingIDs.contains($0.ID) }
        let items = buildNewItems(from: newMessages)
        
        insertItems(items, into: &snapshot, updateType: updateType)
        insertReadMarkerIfNeeded(newMessages, items: items, into: &snapshot, updateType: updateType)
        applyVirtualization(on: &snapshot, updateType: updateType, windowSize: windowSize)
        
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    // MARK: - Private Helpers for addMessages
    private func reloadDeletedMessages(_ messages: [ChatMessage]) {
        // 1) 최신 상태를 먼저 캐시
        for msg in messages { messageMap[msg.ID] = msg }

        // 2) 스냅샷에서 실제로 존재하는 동일 ID 아이템만 추려서 reload
        var snapshot = dataSource.snapshot()
        let targetIDs = Set(messages.map { $0.ID })
        let itemsToReload = snapshot.itemIdentifiers.filter { item in
            if case let .message(m) = item { return targetIDs.contains(m.ID) }
            return false
        }

        guard !itemsToReload.isEmpty else { return }
        snapshot.reloadItems(itemsToReload)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func buildNewItems(from newMessages: [ChatMessage]) -> [Item] {
        var items: [Item] = []
        for message in newMessages {
            messageMap[message.ID] = message
            let messageDate = Calendar.current.startOfDay(for: message.sentAt ?? Date())
            if lastMessageDate == nil || lastMessageDate! != messageDate {
                items.append(.dateSeparator(message.sentAt ?? Date()))
                lastMessageDate = messageDate
            }
            items.append(.message(message))
        }
        return items
    }

    private func insertItems(_ items: [Item], into snapshot: inout NSDiffableDataSourceSnapshot<Section, Item>, updateType: MessageUpdateType) {
        if updateType == .older {
            if let firstItem = snapshot.itemIdentifiers.first {
                snapshot.insertItems(items, beforeItem: firstItem)
            } else {
                snapshot.appendItems(items, toSection: .main)
            }
        } else {
            snapshot.appendItems(items, toSection: .main)
        }
    }

    private func insertReadMarkerIfNeeded(_ newMessages: [ChatMessage], items: [Item], into snapshot: inout NSDiffableDataSourceSnapshot<Section, Item>, updateType: MessageUpdateType) {
        let hasReadMarker = snapshot.itemIdentifiers.contains { if case .readMarker = $0 { return true } else { return false } }
        if updateType == .newer, !hasReadMarker, let lastMessageID = self.lastReadMessageID, !isUserInCurrentRoom,
           let firstMessage = newMessages.first, firstMessage.ID != lastMessageID {
            if let firstNewItem = items.first(where: { if case .message = $0 { return true } else { return false } }) {
                snapshot.insertItems([.readMarker], beforeItem: firstNewItem)
            }
        }
    }

    private func applyVirtualization(on snapshot: inout NSDiffableDataSourceSnapshot<Section, Item>, updateType: MessageUpdateType, windowSize: Int) {
        let allItems = snapshot.itemIdentifiers
        if allItems.count > windowSize {
            let toRemoveCount = allItems.count - windowSize
            if updateType == .older {
                let itemsToRemove = Array(allItems.suffix(toRemoveCount))
                snapshot.deleteItems(itemsToRemove)
            } else if updateType == .newer {
                let itemsToRemove = Array(allItems.prefix(toRemoveCount))
                snapshot.deleteItems(itemsToRemove)
            }
        }
        // --- Virtualization cleanup: prune messageMap and date separators ---
        let allItemsAfterVirtualization = snapshot.itemIdentifiers
        let remainingMessageIDs: Set<String> = Set(
            allItemsAfterVirtualization.compactMap { item in
                if case .message(let m) = item { return m.ID } else { return nil }
            }
        )
        messageMap = messageMap.filter { remainingMessageIDs.contains($0.key) }
        var dateSeparatorsToDelete: [Item] = []
        let presentMessageDates: Set<Date> = Set(
            allItemsAfterVirtualization.compactMap { item in
                if case .message(let m) = item {
                    return Calendar.current.startOfDay(for: m.sentAt ?? Date())
                }
                return nil
            }
        )
        for item in allItemsAfterVirtualization {
            if case .dateSeparator(let date) = item {
                let day = Calendar.current.startOfDay(for: date)
                if !presentMessageDates.contains(day) {
                    dateSeparatorsToDelete.append(item)
                }
            }
        }
        if !dateSeparatorsToDelete.isEmpty {
            snapshot.deleteItems(dateSeparatorsToDelete)
        }
        // --- End of cleanup ---
    }
    
    private func updateCollectionView(with newItems: [Item]) {
        var snapshot = dataSource.snapshot()
        snapshot.appendItems(newItems, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: false)
        chatMessageCollectionView.scrollToBottom()
    }
    
    private func formatDateToDayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.dateFormat = "yyyy년 M월 d일 EEEE"
        return formatter.string(from: date)
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
            guard let animationDuration = sender.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
                  let _ = sender.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else { return }
    
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
        guard let animationDuration = sender.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
              let _ = sender.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        
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
        alert.addAction(UIAlertAction(title: "확인", style: .default) { action in
            self.navigationController?.popViewController(animated: true)
        })
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
            participantCount: room.participants.count,
            target: self,
            onBack: #selector(backButtonTapped),
            onSearch: #selector(searchButtonTapped),
            onSetting: #selector(settingButtonTapped)
        )
    }
}

extension ChatViewController: UIScrollViewDelegate {
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        triggerShakeIfNeeded()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        triggerShakeIfNeeded()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            triggerShakeIfNeeded()
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
        if indexPath.item < 5, hasMoreOlder, !isLoadingOlder {
            if let lastIndex = Self.lastTriggeredOlderIndex,
               abs(lastIndex - indexPath.item) < minTriggerDistance {
                return // 너무 가까운 위치에서 또 호출 → 무시
            }
            Self.lastTriggeredOlderIndex = indexPath.item

            Task {
                let firstID = dataSource.snapshot().itemIdentifiers.compactMap { item -> String? in
                    if case let .message(msg) = item { return msg.ID }
                    return nil
                }.first
                await loadOlderMessages(before: firstID)
            }
        }

        // ✅ Newer 메시지 로드
        if indexPath.item > itemCount - 5, hasMoreNewer, !isLoadingNewer {
            if let lastIndex = Self.lastTriggeredNewerIndex,
               abs(lastIndex - indexPath.item) < minTriggerDistance {
                return
            }
            Self.lastTriggeredNewerIndex = indexPath.item

            Task {
                let lastID = dataSource.snapshot().itemIdentifiers.compactMap { item -> String? in
                    if case let .message(msg) = item { return msg.ID }
                    return nil
                }.last
                await loadNewerMessagesIfNeeded(after: lastID)
            }
        }
    }
}
