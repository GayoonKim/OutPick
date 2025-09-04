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
    var isRoomSaving = false
    
    var convertImagesTask: Task<Void, Error>? = nil
    var convertVideosTask: Task<Void, Error>? = nil
    
    private var filteredMessages: [ChatMessage] = []
    private var currentFilteredMessageIndex: Int?
    private var highlightedMessageIDs: Set<String> = []
    private var currentSearchKeyword: String? = nil
    
    deinit {
        SocketIOManager.shared.closeConnection()
        convertImagesTask?.cancel()
        convertVideosTask?.cancel()
    }
    
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
        view.translatesAutoresizingMaskIntoConstraints = false

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
    
    private let imagesSubject = CurrentValueSubject<[UIImage], Never>([])
    private var imagesPublishser: AnyPublisher<[UIImage], Never> {
        return imagesSubject.eraseToAnyPublisher()
    }

    // Layout 제약 조건 저장
    private var chatConstraints: [NSLayoutConstraint] = []
    private var chatUIViewBottomConstraint: NSLayoutConstraint?
    private var joinConsraints: [NSLayoutConstraint] = []
    
    private var interactionController: UIPercentDrivenInteractiveTransition?
    
    lazy var tapGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture))
        gesture.delegate = self
        return gesture
    }()
    
    lazy var longPressGesture: UILongPressGestureRecognizer = {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        gesture.delegate = self
        return gesture
    }()
    
    private var searchUIBottomConstraint: NSLayoutConstraint?
    
    private var scrollTargetIndex: IndexPath?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureDataSource()
        
        self.attachInteractiveDismissGesture()
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
        bindMessagePublishers()
        bindKeyboardPublisher()
        bindSearchEvents()
        
        chatMessageCollectionView.collectionView.delegate = self
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        Task {
            // 이미 연결된 경우에는 room join과 listener 설정만 수행
            if let room = self.room,
               room.participants.contains(LoginManager.shared.getUserEmail) {
                
                let messages = try await GRDBManager.shared.fetchMessages(in: room.ID ?? "", containing: nil)
                let lastMessageID = try await GRDBManager.shared.fetchLastMessageID(for: room.ID ?? "")

                addMessages(messages, isNew: false)
                lastReadMessageID = lastMessageID
                
                print(#function, "✅✅✅✅✅✅✅✅✅✅ 마지막 메시지 ID:", lastMessageID ?? "")

                try await self.syncMessagesIfNeeded(for: room)
                
                isUserInCurrentRoom = true

                if !SocketIOManager.shared.isConnected {
                    SocketIOManager.shared.establishConnection { [weak self] in
                        guard let _ = self else { return }
                        SocketIOManager.shared.joinRoom(room.ID ?? "")
                        SocketIOManager.shared.socket.off("chat message")
                        SocketIOManager.shared.listenToChatMessage()
                        SocketIOManager.shared.listenToNewParticipant()
                    }
                }
                
                self.bindRoomChangePublisher()
            }
            
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        cancellables.removeAll()

        if let topVC = self.navigationController?.topViewController,
           topVC is ChatRoomSettingCollectionView {
            return
        } else {
            SocketIOManager.shared.closeConnection()
        }
    
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
    }

    //MARK: 메시지 관련
    private func bindMessagePublishers() {
        // 메시지 수신 관련
        SocketIOManager.shared.receivedMessagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] receivedMessage in
                guard let self = self else { return }
                
                print("\(receivedMessage.isFailed ? "전송 실패" : "전송 성공") 메시지 수신: \(receivedMessage)")
                guard let room = self.room else { return }
                
                Task {
                    if  !receivedMessage.isFailed ,receivedMessage.senderID == LoginManager.shared.getUserEmail {
                        // ✅ 보낸 본인만 Firebase에 저장
                        try await FirebaseManager.shared.saveMessage(receivedMessage, room)
                    }
                    
                    try await GRDBManager.shared.saveChatMessage(receivedMessage)
                    
                    if !receivedMessage.attachments.isEmpty {
                        for attachment in receivedMessage.attachments {
                            guard attachment.type == .image, let imageName = attachment.fileName else { continue }
                            
                            if !receivedMessage.isFailed {
                                try GRDBManager.shared.addImage(imageName, toRoom: room.ID ?? "", at: receivedMessage.sentAt ?? Date())
                            }
                            
                            if let image = attachment.toUIImage() {
                                try await KingfisherManager.shared.cache.store(image, forKey: imageName)
                            }
                        }
                    }
                }
                
                addMessages([receivedMessage], isNew: false)
            }
            .store(in: &cancellables)
    }
    
    @MainActor
    private func setupChatUI() {
        if chatUIView.superview == nil {
            view.addSubview(chatUIView)
            view.addSubview(chatMessageCollectionView)
            chatMessageCollectionView.translatesAutoresizingMaskIntoConstraints = false
            chatUIView.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.deactivate(joinConsraints)
        
        chatUIViewBottomConstraint = chatUIView.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -10)
        chatConstraints = [
            chatUIViewBottomConstraint!,
            chatUIView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 8),
            chatUIView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -8),
            chatUIView.heightAnchor.constraint(greaterThanOrEqualToConstant: chatUIView.minHeight),

            chatMessageCollectionView.topAnchor.constraint(equalTo: customNavigationBar.bottomAnchor),
            chatMessageCollectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chatMessageCollectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chatMessageCollectionView.bottomAnchor.constraint(greaterThanOrEqualTo: chatUIView.topAnchor)
        ]
        NSLayoutConstraint.activate(chatConstraints)
    }
    
    @MainActor
    private func handleSendButtonTap() {
        guard let message = self.chatUIView.messageTextView.text,
              let room = self.room else { return }
        DispatchQueue.main.async {
            print(self.chatUIView.messageTextView.frame.width)
            self.chatUIView.messageTextView.text = nil
            self.chatUIView.updateHeight()
        }
        
        let newMessage = ChatMessage(roomID: room.ID ?? "", senderID: LoginManager.shared.getUserEmail, senderNickname: LoginManager.shared.currentUserProfile?.nickname ?? "", msg: message, sentAt: Date(), attachments: [])
        
        SocketIOManager.shared.sendMessages(room, newMessage)
        chatUIView.sendButton.isEnabled = false
    }
    
    @MainActor
    private func syncMessagesIfNeeded(for room: ChatRoom, reset: Bool = true) async throws {
        do {
            let messages = try await FirebaseManager.shared.fetchMessagesPaged(for: room)
            print(#function, "✅ 호출 완료: ", messages.count)
            
            for message in messages {
                try await GRDBManager.shared.saveChatMessage(message)
                
                if !message.attachments.isEmpty {
                    await withTaskGroup(of: Void.self) { group in
                        for attachment in message.attachments {
                            guard attachment.type == .image, let imageName = attachment.fileName else { continue }
                            try? GRDBManager.shared.addImage(imageName, toRoom: room.ID ?? "", at: message.sentAt ?? Date())
                            
                            group.addTask {
                                if let image = attachment.toUIImage() {
                                    try? await KingfisherManager.shared.cache.store(image, forKey: imageName)
                                }
                            }
                        }
                    }
                }
            }
            
            /*chatMessageCollectionView.*/addMessages(messages, isNew: true)
        } catch {
            print("❌ 메시지 동기화 실패: \(error)")
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
        // 실시간 방 업데이트 관련
        FirebaseManager.shared.roomChangePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] updatedRoom in
                guard let self = self,
                      let _ = self.room else { return }
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
            } else {
                // 연결되지 않은 경우에만 연결 시도
                SocketIOManager.shared.establishConnection {
                    SocketIOManager.shared.createRoom(savedRoom.roomName)
                    SocketIOManager.shared.joinRoom(savedRoom.roomName)
                }
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
            
            for profile in profiles {
                try GRDBManager.shared.insertUserProfile(profile)
                try GRDBManager.shared.addUser(profile.email ?? "", toRoom: room?.ID ?? "")
            }
            
            print(#function, "✅ 사용자 프로필 동기화 성공: ", profiles)
        } catch {
            print("❌ 사용자 프로필 동기화 실패: \(error)")
        }
    }

    
    //MARK: 초기 UI 설정 관련
    @MainActor
    private func decideJoinUI() {
        guard let room = room else { return }

        Task {
            // 이제 메인 스레드니까 바로 UI 업데이트 가능
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
        self.customNavigationBar.rightStack.isUserInteractionEnabled = true

        Task {
            do {
                // 1. Firebase에 참여자 등록
                try await FirebaseManager.shared.add_room_participant(room: room)
                // 2. 소켓을 통해 다른 참여자에게 알림
                SocketIOManager.shared.notifyNewParticipant(roomID: room.ID ?? "", email: LoginManager.shared.currentUserProfile?.email ?? "")
                
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5초 대기
                
                let updatedRoom = try await FirebaseManager.shared.fetchRoomInfo(room: room)
                self.room = updatedRoom
                self.updateNavigationTitle(with: updatedRoom)
                try await self.syncProfilesWithLocalDB(emails: updatedRoom.participants)
                
                // 4. UI 업데이트
                setupChatUI()
                chatUIView.isHidden = false
                chatMessageCollectionView.isHidden = false
                NSLayoutConstraint.deactivate(joinConsraints)
                chatConstraints.append(chatMessageCollectionView.bottomAnchor.constraint(equalTo: chatUIView.topAnchor))
                NSLayoutConstraint.activate(chatConstraints)
            } catch {
                print("방 참여 처리 실패: \(error)")
            }
        }
    }

    //MARK: 커스텀 내비게이션 바
    @MainActor
    /*@objc */private func backButtonTapped() {
        
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
        } else {
            // 일반적인 경우 이전 화면으로 이동
            ChatModalTransitionManager.dismiss(from: self)
        }
    }
    
    private func settingButtonTapped() {
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
            
            let settingVC = ChatRoomSettingCollectionView(room: room, profiles: profiles, images: images)
            settingVC.modalPresentationStyle = .fullScreen
            
            ChatModalTransitionManager.present(settingVC, from: self)
        }
    }
    
    @MainActor
    private func updateNavigationTitle(with room: ChatRoom) {
        // ✅ 커스텀 내비게이션 바 타이틀 업데이트
            customNavigationBar.configureForChatRoom(
                /*unreadCount: 99,*/ // 필요한 경우 여기도 업데이트 필요
                roomTitle: room.roomName,
                participantCount: room.participants.count,
                onBack: backButtonTapped,
                onSearch: searchButtonTapped,
                onSetting: settingButtonTapped
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

        if let cell = chatMessageCollectionView.collectionView.cellForItem(at: indexPath) as? ChatMessageCell {
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
            searchUIBottomConstraint = searchUI.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10)
            
            NSLayoutConstraint.activate([
                searchUI.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                searchUI.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
                searchUIBottomConstraint!,
                searchUI.heightAnchor.constraint(equalToConstant: 50)
            ])
        }
    }
    
    @MainActor
    private func searchButtonTapped() {
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
        guard let cell = chatMessageCollectionView.collectionView.cellForItem(at: indexPath) as? ChatMessageCell,
              let item = dataSource.itemIdentifier(for: indexPath),
              case let .message(message) = item else { return }
        
        // 1.셀 강조하기
        cell.setHightlightedOverlay(true)
        highlightedCell = cell
        
        // 셀의 bounds 기준으로 컬렉션뷰 내 프레임 계산
        let cellFrameInCollection = cell.convert(cell.bounds, to: chatMessageCollectionView.collectionView)
        let cellCenterY = cellFrameInCollection.midY

        // 컬렉션 뷰 기준 중앙 사용 (화면 절반)
        let screenMiddleY = chatMessageCollectionView.collectionView.bounds.midY
        let showAbove: Bool = cellCenterY > screenMiddleY
        
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
    }
    
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let location = gesture.location(in: chatMessageCollectionView.collectionView)
        guard let indexPath = chatMessageCollectionView.collectionView.indexPathForItem(at: location) else { return }

        showCustomMenu(at: indexPath)
    }
    
    private func handleReply(message: ChatMessage) {
        print(#function, "답장:", message)
        
        // 답장 로직 구현
        
    }

    private func handleCopy(message: ChatMessage) {
        UIPasteboard.general.string = message.msg
        print(#function, "복사:", message.msg ?? "")
        // 필요 시 UI 피드백
    }

    private func handleDelete(message: ChatMessage) {
        // 삭제 로직 구현 (Diffable Data Source snapshot 업데이트 등)
        print(#function, "삭제:", message)
    }
    
    private func dismissCustomMenu() {
        if let cell = highlightedCell { cell.setHightlightedOverlay(false) }
        highlightedCell = nil
        chatCustomMenu.removeFromSuperview()
    }
    
    //MARK: Diffable Data Source
        private func configureDataSource() {
            print(#function)
            dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: chatMessageCollectionView.subviews.compactMap{ $0 as? UICollectionView }.first!) { collectionView, indexPath, item in
    
                switch item {
                case .message(let message):
                    let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ChatMessageCell.reuseIdentifier, for: indexPath) as! ChatMessageCell
                    
                    if message.attachments.isEmpty {
                        cell.configureWithMessage(with: message)
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
    
        func addMessages(_ messages: [ChatMessage], isNew: Bool) {
            print("************************ \(#function) 호출 ************************")
    
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
                let messageDate = Calendar.current.startOfDay(for: message.sentAt ?? Date())
    
                if lastMessageDate == nil || lastMessageDate! != messageDate {
                    items.append(.dateSeparator(message.sentAt ?? Date()))
                    lastMessageDate = messageDate
                }
    
                items.append(.message(message))
            }
    
            updateCollectionView(with: items)
    
            if !hasReadMarker, let lastMessageID = self.lastReadMessageID, !isUserInCurrentRoom, isNew,
               let firstMessage = newMessages.first,
               firstMessage.ID != lastMessageID {
    
                var updatedSnapshot = dataSource.snapshot()
                let firstNewItem = items.first(where: {
                    if case .message = $0 { return true }
                    return false
                })
    
                if let firstNewItem = firstNewItem {
                    updatedSnapshot.insertItems([.readMarker], beforeItem: firstNewItem)
                    dataSource.apply(updatedSnapshot, animatingDifferences: false)
                }
            }
    
        }
    
        private func updateCollectionView(with newItems: [Item]) {
    //        print("************************ \(#function) 호출 ************************")
    
            var snapshot = dataSource.snapshot()
            snapshot.appendItems(newItems, toSection: .main)
    //        print("Before apply, snapshot items: \(snapshot.itemIdentifiers)") // 추가된 아이템 확인
    
            dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
                guard let self = self else { return }
    //            print("************************ Apply 완료, snapshot items: \(snapshot.itemIdentifiers) ************************")
                chatMessageCollectionView.scrollToBottom()
            }
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
    @objc private func handleTapGesture() {
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
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self else { return }
                self.keyboardWillShow(notification)
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.keyboardWillHideNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self else { return }
                self.keyboardWillHide(notification)
            }
            .store(in: &cancellables)
    }
    
    @objc private func keyboardWillShow(_ sender: Notification) {
        guard let keyboardFrame = sender.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let animationDuration = sender.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }

        // Hide attachment view if visible
        let keyboardFrameHeight = keyboardFrame.height
        let safeAreaBottom = self.view.safeAreaInsets.bottom
        
        if !self.attachmentView.isHidden {
            self.attachmentView.isHidden = true
            self.chatUIView.attachmentButton.setImage(UIImage(systemName: "plus"), for: .normal)
        }

        let bottomConstraint = -(keyboardFrameHeight - safeAreaBottom + 10)
        chatUIViewBottomConstraint?.constant = bottomConstraint
        searchUIBottomConstraint?.constant = bottomConstraint
        
        UIView.animate(withDuration: animationDuration) {
            self.view.layoutIfNeeded()
        }
        
        UIView.animate(withDuration: animationDuration, animations: {
            self.view.layoutIfNeeded()
        }, completion: { _ in
            // ✅ 키보드 올라온 뒤 스크롤 아래로
            self.chatMessageCollectionView.scrollToBottom()
        })
    }
    
    @objc private func keyboardWillHide(_ sender: Notification) {
        guard let animationDuration = sender.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }
        chatUIViewBottomConstraint?.constant = -10
        searchUIBottomConstraint?.constant = -10
        
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
            customNavigationBar.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            customNavigationBar.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            customNavigationBar.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
        ])
        
        guard let room = self.room else { return }
        customNavigationBar.configureForChatRoom(/*unreadCount: 99, */roomTitle: room.roomName, participantCount: room.participants.count, onBack: backButtonTapped, onSearch: searchButtonTapped, onSetting: settingButtonTapped)
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
              let cell = chatMessageCollectionView.collectionView.cellForItem(at: indexPath) as? ChatMessageCell else {
            return
        }
        cell.shakeHorizontally()
        scrollTargetIndex = nil  // 초기화
    }
}
