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

class ChatViewController: UIViewController, UINavigationControllerDelegate, ChatModalAnimatable, UICollectionViewDelegate {

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
    
    enum Section: Hashable {
        case main
    }
    
    enum Item: Hashable {
        case message(ChatMessage)
        case dateSeparator(Date)
        case readMarker
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
    
    deinit {
        print("💧 ChatViewController deinit")
        convertImagesTask?.cancel()
        convertVideosTask?.cancel()
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
//
//    init(room: ChatRoom, isRoomSaving: Bool = false) {
//        self.room = room
//        self.isRoomSaving = isRoomSaving
//        super.init(nibName: nil, bundle: nil)
//    }
//
//    required init?(coder: NSCoder) {
//        fatalError("init(coder:) has not been implemented")
//    }
//
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
        // ✅ 초기 네트워크/메모리 상태 기반으로 pagingBuffer 세팅
        pagingBuffer = PagingBufferCalculator.calculate(
            for: room,
            scrollVelocity: 0 // 아직 스크롤 속도 없음
        )
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
        bindMessagePublishers()
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
                // GRDB + Firebase 동시 실행
                async let local = GRDBManager.shared.fetchRecentMessages(inRoom: room.ID ?? "", limit: 200)
                async let server = FirebaseManager.shared.fetchMessagesPaged(for: room, pageSize: 300, reset: true)
                
                let (localMessages, serverMessages) = try await (local, server)
                
                print(#function, "✅ GRDB 최근 메시지 200개 로드 완료.", localMessages)
                print(#function, "✅ Firebase 최근 메시지 300개 로드 및 GRDB 저장 완료.", serverMessages)
                
                // GRDB 먼저 반영 → UI 빠른 응답
                addMessages(localMessages)
                self.lastReadMessageID = localMessages.last?.ID
                
                // 서버 메시지 저장 + 반영
                try await GRDBManager.shared.saveChatMessages(serverMessages)
                addMessages(serverMessages, isNewer: true)
                
                isUserInCurrentRoom = true
            } catch {
                print("❌ 메시지 초기화 실패:", error)
            }
            isInitialLoading = false
        }
    }

    // MARK: - 메시지 페이징 로드
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
        if isLoadingOlder { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        guard let room = self.room else { return }
        print(#function, "✅ loading older 진행")
        do {
            // 1. GRDB에서 먼저 최대 100개
            let local = try await GRDBManager.shared.fetchOlderMessages(inRoom: room.ID ?? "", before: messageID ?? "", limit: 100)
            var loadedMessages = local

            // 2. 부족분은 서버에서 채우기
            if local.count < 100 {
                let needed = 100 - local.count
                let server = try await FirebaseManager.shared.fetchOlderMessages(for: room, before: messageID ?? "", limit: needed)
                try await GRDBManager.shared.saveChatMessages(server)
                loadedMessages.append(contentsOf: server)
            }

            addMessages(loadedMessages, isOlder: true)
        } catch {
            print("❌ loadOlderMessages 실패:", error)
        }
    }

    @MainActor
    private func loadNewerMessagesIfNeeded(after messageID: String?) async {
        if isLoadingNewer { return }
        isLoadingNewer = true
        defer { isLoadingNewer = false }
        guard let room = self.room else { return }
        print(#function, "✅ loading newer 진행")
        do {
            // 1. 서버에서 lastMessageID 이후 메시지 보충 (최대 100개)
            let server = try await FirebaseManager.shared.fetchMessagesAfter(room: room, after: messageID ?? "", limit: 100)
            try await GRDBManager.shared.saveChatMessages(server)
            addMessages(server, isNewer: true)
        } catch {
            print("❌ loadNewerMessagesIfNeeded 실패:", error)
        }
    }

    private func bindMessagePublishers() {
        print(#function, "✅✅✅✅✅ 1. SocketIOManager.shared.subscribeToMessages 호출 직전")
        
        guard let room = self.room else { return }
        SocketIOManager.shared.subscribeToMessages(for: room.ID ?? "")
            .sink { [weak self] receivedMessage in
                guard let self = self else { return }
                Task {
                    print(#function, "handleIncomingMessage 호출")
                    await self.handleIncomingMessage(receivedMessage)
                }
            }
            .store(in: &cancellables)
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
            
            addMessages([message], isNewer: true)
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
        
        let newMessage = ChatMessage(roomID: room.ID ?? "", senderID: LoginManager.shared.getUserEmail, senderNickname: LoginManager.shared.currentUserProfile?.nickname ?? "", msg: message, sentAt: Date(), attachments: [], replyPreview: replyMessage)
        
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
                guard let self = self
                      /*let _ = self.room*/ else { return }
                print(#function, "ChatViewController.swift 방 정보 변경: \(updatedRoom)")
                self.room = updatedRoom
                Task { @MainActor in
                    self.updateNavigationTitle(with: updatedRoom)
                    try await self.syncProfilesWithLocalDB(emails: updatedRoom.participants)
                }
            }
            .store(in: &cancellables)
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
//                    self.updateNavigationTitle(with: updatedRoom)
                    self.setupChatUI()
                    self.chatUIView.isHidden = false
                    self.chatMessageCollectionView.isHidden = false
                    self.bindRoomChangePublisher()
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
//            settingVC.modalPresentationStyle = .fullScreen
//            present(settingVC, animated: true)
//            settingVC.modalPresentationStyle = .custom
//            settingVC.transitioningDelegate = self.sidePanelTransitioningDelegate
//            self.present(settingVC, animated: true)
            self.presentSettingVC(settingVC)
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
              case let .message(message) = item else { return }
        
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
            chatCustomMenu.configurePrimaryActionMode(canDelete: isOwner || isAdmin)
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
            self.handleDelete(message: message)
            self.dismissCustomMenu()
        }
        chatCustomMenu.onReport = { [weak self] in
            self?.handleReport(message: message)
            self?.dismissCustomMenu()
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
        print(#function, "복사:", message.msg ?? "")
        // 필요 시 UI 피드백
        showSuccess("메시지가 복사되었습니다.")
    }
    
    private func handleDelete(message: ChatMessage) {
        // 삭제 로직 구현 (Diffable Data Source snapshot 업데이트 등)
        print(#function, "삭제:", message)
    }
    
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let location = gesture.location(in: chatMessageCollectionView/*.collectionView*/)
        guard let indexPath = chatMessageCollectionView.indexPathForItem(at: location) else { return }
        
        showCustomMenu(at: indexPath)
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
        print(#function)
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: chatMessageCollectionView) { [weak self] collectionView, indexPath, item in
            guard let self = self else { return  nil }
            
            switch item {
            case .message(let message):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ChatMessageCell.reuseIdentifier, for: indexPath) as! ChatMessageCell
                
                if message.attachments.isEmpty {
                    cell.configureWithMessage(with: message/*, originalPreviewProvider: originalPreviewClosure*/)
                } else {
                    cell.configureWithImage(with: message)
                }
                
                let keyword = self.highlightedMessageIDs.contains(message.ID) ? self.currentSearchKeyword : nil
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
    func addMessages(_ messages: [ChatMessage], isOlder: Bool = false, isNewer: Bool = false) {
        var items: [Item] = []
        
        let snapshot = dataSource.snapshot()
        let existingIDs = snapshot.itemIdentifiers.compactMap { item -> String? in
            if case .message(let m) = item { return m.ID }
            return nil
        }
        
        let newMessages = messages.filter { !existingIDs.contains($0.ID) }
        
        let hasReadMarker = snapshot.itemIdentifiers.contains { item in
            if case .readMarker = item { return true }
            return false
        }
        
        for message in newMessages {
            messageMap[message.ID] = message
            let messageDate = Calendar.current.startOfDay(for: message.sentAt ?? Date())
            
            if lastMessageDate == nil || lastMessageDate! != messageDate {
                items.append(.dateSeparator(message.sentAt ?? Date()))
                lastMessageDate = messageDate
            }
            
            items.append(.message(message))
        }
        
        var updatedSnapshot = snapshot
        if isOlder {
            if let firstItem = snapshot.itemIdentifiers.first {
                updatedSnapshot.insertItems(items, beforeItem: firstItem)
            } else {
                updatedSnapshot.appendItems(items, toSection: .main)
            }
        } else if isNewer {
            updatedSnapshot.appendItems(items, toSection: .main)
        } else {
            updatedSnapshot.appendItems(items, toSection: .main)
        }
        
        // Insert readMarker only for newer messages
        if isNewer, !hasReadMarker, let lastMessageID = self.lastReadMessageID, !isUserInCurrentRoom,
           let firstMessage = newMessages.first, firstMessage.ID != lastMessageID {
            
            if let firstNewItem = items.first(where: { if case .message = $0 { return true }; return false }) {
                updatedSnapshot.insertItems([.readMarker], beforeItem: firstNewItem)
            }
        }
        
        dataSource.apply(updatedSnapshot, animatingDifferences: false)
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

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
//        guard !isInitialLoading else { return }
//
//        let velocityY = scrollView.panGestureRecognizer.velocity(in: scrollView).y
//        pagingBuffer = PagingBufferCalculator.calculate(
//            for: room,
//            scrollVelocity: abs(velocityY)
//        )
//
//        // 현재 보이는 indexPaths
//        let visibleIndexPaths = chatMessageCollectionView.indexPathsForVisibleItems
//        guard !visibleIndexPaths.isEmpty else { return }
//
//        let rows = visibleIndexPaths.map { $0.row }
//        guard let firstVisibleIndex = rows.min(), let lastVisibleIndex = rows.max() else { return }
//
//        let snapshot = dataSource.snapshot()
//        let items = snapshot.itemIdentifiers
//        let totalCount = items.count
//
//        // Prefetch older (맨 위 근처)
//        if firstVisibleIndex <= pagingBuffer, !isLoadingOlder {
//            if firstVisibleIndex < items.count {
//                let firstMessageItem = items[firstVisibleIndex]
//                if case let .message(message) = firstMessageItem {
//                    Task { await loadOlderMessages(before: message.ID) }
//                }
//            }
//        }
//
//        // Prefetch newer (맨 아래 근처)
//        if (totalCount - 1) - lastVisibleIndex <= pagingBuffer, !isLoadingNewer {
//            if lastVisibleIndex < items.count {
//                let lastMessageItem = items[lastVisibleIndex]
//                if case let .message(message) = lastMessageItem {
//                    Task { await loadNewerMessagesIfNeeded(after: message.ID) }
//                }
//            }
//        }
        
        
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
