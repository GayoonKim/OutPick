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

class ChatViewController: UIViewController, UINavigationControllerDelegate, ChatModalAnimatable {
    
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var sideMenuBtn: UIBarButtonItem!
    @IBOutlet weak var joinRoomBtn: UIButton!
    
    var swipeRecognizer: UISwipeGestureRecognizer!
    
    private var dimmingView: UIView?
    
    var room: ChatRoom?
    var roomID: String?
    var isRoomSaving = false
    
    var convertImagesTask: Task<Void, Error>? = nil
    var convertVideosTask: Task<Void, Error>? = nil
    
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

    private lazy var cancellables = Set<AnyCancellable>()
    private let imagesSubject = CurrentValueSubject<[UIImage], Never>([])
    private var imagesPublishser: AnyPublisher<[UIImage], Never> {
        return imagesSubject.eraseToAnyPublisher()
    }
    
    private lazy var chatMessageCollectionView = ChatMessageCollectionView()
    
    // Layout 제약 조건 저장
    private var chatConstraints: [NSLayoutConstraint] = []
    private var chatUIViewBottomConstraint: NSLayoutConstraint?
    private var joinConsraints: [NSLayoutConstraint] = []
    
    private var interactionController: UIPercentDrivenInteractiveTransition?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.attachInteractiveDismissGesture()
        setUpNotifications()
        
        if isRoomSaving {
            LoadingIndicator.shared.start(on: self)
            chatUIView.isHidden = false
            joinRoomBtn.isHidden = true
        } else {
            LoadingIndicator.shared.stop()
        }
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture))
        tapGesture.delegate = self
        view.addGestureRecognizer(tapGesture)

        setupCustomNavigationBar()
        decideJoinUI()
        setupAttachmentView()
        bindPublishers()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // 이미 연결된 경우에는 room join과 listener 설정만 수행
        if SocketIOManager.shared.isConnected {
            SocketIOManager.shared.socket.off("chat message")
            if let roomName = self.room?.roomName {
                SocketIOManager.shared.joinRoom(roomName)
            }
            SocketIOManager.shared.listenToChatMessage()
            SocketIOManager.shared.listenToNewParticipant()
        } else {
            // 연결되지 않은 경우에만 연결 시도
            SocketIOManager.shared.establishConnection { [weak self] in
                guard let self = self else { return }
                SocketIOManager.shared.socket.off("chat message")
                if let roomName = self.room?.roomName {
                    SocketIOManager.shared.joinRoom(roomName)
                }
                SocketIOManager.shared.listenToChatMessage()
                SocketIOManager.shared.listenToNewParticipant()
            }
        }
        
        if let room = self.room {
            if room.participants.contains(LoginManager.shared.getUserEmail) {
                
            }
        }
        
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if let topVC = self.navigationController?.topViewController,
           topVC is ChatRoomSettingCollectionView {
            return
        }
        
        SocketIOManager.shared.closeConnection()
        
//        guard let room = self.room else { return }
//        if !room.participants.contains(LoginManager.shared.getUserEmail) {
//            ChatUserProfilesStoreManager.shared.clearUserProfiles(forRoomName: room.roomName)
//        }
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
            chatUIView.heightAnchor.constraint(equalToConstant: chatUIView.minHeight),

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
        
        let newMessage = ChatMessage(roomName: room.roomName,senderID: LoginManager.shared.getUserEmail, senderNickname: LoginManager.shared.currentUserProfile?.nickname ?? "", msg: message, sentAt: Date(), attachments: [])
        
        SocketIOManager.shared.sendMessages(room, newMessage)
        chatUIView.sendButton.isEnabled = false
    }

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
    
    private func bindPublishers() {
        // 메시지 수신 관련
        SocketIOManager.shared.receivedMessagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] receivedMessage in
                guard let self = self else { return }
                
                print("\(receivedMessage.isFailed ? "전송 실패" : "전송 성공") 메시지 수신: \(receivedMessage)")
                if let room = self.room {
                    if !receivedMessage.isFailed {
                        Task { try await FirebaseManager.shared.saveMessage(receivedMessage, room) }
                        
                        if !receivedMessage.attachments.isEmpty {
                            let images = receivedMessage.attachments.compactMap{ $0.toUIImage() }
                            ChatImageStoreManager.shared.addImages(images, for: receivedMessage.roomName)
                            imagesSubject.send(images)
                        }
                    }
                }
                chatMessageCollectionView.addMessage(with: receivedMessage)
            }
            .store(in: &cancellables)
        
        // 실시간 방 업데이트 관련
        FirebaseManager.shared.roomChangePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] updatedRoom in
                guard let self = self,
                      let _ = self.room else { return }
                self.room = updatedRoom
                self.updateNavigationTitle(with: updatedRoom)
            }
            .store(in: &cancellables)
        
        // 키보드 관련
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
    
    private func setUpNotifications() {
        // 방 저장 관련
        NotificationCenter.default.addObserver(self, selector: #selector(handleRoomSaveCompleted), name: .roomSavedComplete, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRoomSaveFailed), name: .roomSaveFailed, object: nil)
    }
    
    private func playVideo(from url: URL) {
        let asset = AVAsset(url: url)
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
    private func decideJoinUI() {
        guard let room = room else { return }

        Task {
            if !ChatUserProfilesStoreManager.shared.hasProfiles(forRoomName: room.roomName) {
                do {
                    let profiles = try await FirebaseManager.shared.fetchUserProfiles(emails: room.participants)
                    ChatUserProfilesStoreManager.shared.saveUserProfiles(profiles, forRoomName: room.roomName)
                } catch {
                    print("프로필 데이터 가져오기 실패: \(error)")
                }
            }

            // 이제 메인 스레드니까 바로 UI 업데이트 가능
            if room.participants.contains(LoginManager.shared.getUserEmail) {
                setupChatUI()
                chatUIView.isHidden = false
                joinRoomBtn.isHidden = true
            } else {
                setJoinRoombtn()
                joinRoomBtn.isHidden = false
                chatUIView.isHidden = true
            }
            
            updateNavigationTitle(with: room)
        }
        
        print("All Participants: \(ChatUserProfilesStoreManager.shared.getUserProfiles(forRoomName: room.roomName))")
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
    private func updateNavigationTitle(with room: ChatRoom) {
        self.navigationItem.setTitle(title: room.roomName, subtitle: "\(room.participants.count)명 참여")
    }
    
    @MainActor
    @IBAction func joinRoomBtnTapped(_ sender: UIButton) {
        guard let room = self.room else { return }

        joinRoomBtn.isHidden = true

        Task {
            do {
                // 1. Firebase에 참여자 등록
                try await FirebaseManager.shared.add_room_participant(room: room)
                // 2. 소켓을 통해 다른 참여자에게 알림
                SocketIOManager.shared.notifyNewParticipant(roomName: room.roomName, email: LoginManager.shared.currentUserProfile?.email ?? "")
                
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5초 대기
                
                let updatedRoom = try await FirebaseManager.shared.fetchRoomInfo(room: room)
                self.room = updatedRoom
                
                // 3. 전체 프로필 동기화
                let profiles = try await FirebaseManager.shared.fetchUserProfiles(emails: updatedRoom.participants)
                ChatUserProfilesStoreManager.shared.saveUserProfiles(profiles, forRoomName: room.roomName)

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

        self.chatUIViewBottomConstraint?.constant = -(keyboardFrameHeight - safeAreaBottom + 10)
        
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
        self.chatUIViewBottomConstraint?.constant = -10
        
        UIView.animate(withDuration: animationDuration) {
            self.view.layoutIfNeeded()
        }
    }
    
    @objc private func handleTapGesture() {
        chatUIView.messageTextView.resignFirstResponder()
        
        if !self.attachmentView.isHidden {
            
            chatUIView.attachmentButton.setImage(UIImage(systemName: "plus"), for: .normal)
            self.attachmentView.isHidden = true
            self.attachmentView.alpha = 0

            self.chatUIViewBottomConstraint?.constant = -10

            UIView.animate(withDuration: 0.25) {
                self.view.layoutIfNeeded()
            }
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
    
    @MainActor
    /*@objc */private func backButtonTapped() {
        
        let transition = CATransition()
        transition.duration = 0.3
        transition.type = .push
        transition.subtype = .fromLeft // 왼쪽에서 오른쪽으로 이동 (pop 느낌)
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        self.view.window?.layer.add(transition, forKey: kCATransition)
        
        if isRoomSaving {
            // 방 생성 화면에서 왔을 경우 RoomListsCollectionViewController로 이동
//            if let roomListsVC = self.navigationController?.viewControllers.first(where: { $0 is RoomListsCollectionViewController }) {
//                self.navigationController?.popToViewController(roomListsVC, animated: true)
//            }
            
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
    
    @MainActor
    /*@objc */private func settingButtonTapped() {
        guard let room = self.room else { return }
        let settingVC = ChatRoomSettingCollectionView(room: room)
        settingVC.modalPresentationStyle = .fullScreen
        
        settingVC.bindImagesPublishers(self.imagesPublishser)
        let profilePublisher = ChatUserProfilesStoreManager.shared.profilesPublisher(forRoomName: room.roomName)
        settingVC.bindProfilesPublisher(profilePublisher)
  
        ChatModalTransitionManager.present(settingVC, from: self)
    }

    @MainActor
    private func searchButtonTapped() {
        print(#function)
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
        customNavigationBar.configureForChatRoom(unreadCount: 99, roomTitle: room.roomName, participantCount: room.participants.count, onBack: backButtonTapped, onSearch: searchButtonTapped, onSetting: settingButtonTapped)
    }
}
