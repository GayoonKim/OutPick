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

class ChatViewController: UIViewController, UINavigationControllerDelegate {
    
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var sideMenuBtn: UIBarButtonItem!
    @IBOutlet weak var joinRoomBtn: UIButton!
    
    var swipeRecognizer: UISwipeGestureRecognizer!
    
    private var sideMenuViewController = SideMenuViewController()
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

    private lazy var cancellables = Set<AnyCancellable>()
    private lazy var chatMessageCollectionView = ChatMessageCollectionView()
    
    // Layout 제약 조건 저장
    private var chatConstraints: [NSLayoutConstraint] = []
    private var chatUIViewBottomConstraint: NSLayoutConstraint?
    private var joinConsraints: [NSLayoutConstraint] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let backButton = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: self, action: #selector(backButtonTapped))
        backButton.tintColor = .black
        self.navigationItem.leftBarButtonItem = backButton
        
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
        
        swipeRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(swipeAction(_:)))
        self.view.addGestureRecognizer(swipeRecognizer)
        
        setupChatMessageCollectionView()
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
        } else {
            // 연결되지 않은 경우에만 연결 시도
            SocketIOManager.shared.establishConnection { [weak self] in
                guard let self = self else { return }
                SocketIOManager.shared.socket.off("chat message")
                if let roomName = self.room?.roomName {
                    SocketIOManager.shared.joinRoom(roomName)
                }
                SocketIOManager.shared.listenToChatMessage()
            }
        }
        
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        SocketIOManager.shared.closeConnection()
    }
    
    private func setupChatMessageCollectionView() {
        view.addSubview(chatMessageCollectionView)
        chatMessageCollectionView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            
            chatMessageCollectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            chatMessageCollectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chatMessageCollectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chatMessageCollectionView.heightAnchor.constraint(equalToConstant: view.frame.height - chatUIView.minHeight)
            
        ])
    }
    
    private func setupChatUI() {
        if chatUIView.superview == nil {
            view.addSubview(chatUIView)
        }

        chatUIView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.deactivate(joinConsraints)
        
        chatUIViewBottomConstraint = chatUIView.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -10)
        chatConstraints = [
            chatUIViewBottomConstraint!,
            chatUIView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 8),
            chatUIView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -8),
            chatUIView.heightAnchor.constraint(greaterThanOrEqualToConstant: chatUIView.minHeight),
            
            chatMessageCollectionView.bottomAnchor.constraint(equalTo: chatUIView.topAnchor)
        ]
        NSLayoutConstraint.activate(chatConstraints)
        
    }
    
    private func handleSendButtonTap() {
        guard let message = self.chatUIView.messageTextView.text,
              let room = self.room else { return }
        DispatchQueue.main.async {
            print(self.chatUIView.messageTextView.frame.width)
            self.chatUIView.messageTextView.text = nil
            self.chatUIView.updateHeight()
        }
        
        let newMessage = ChatMessage(roomName: room.roomName,senderID: LoginManager.shared.getUserEmail, senderNickname: UserProfile.shared.nickname ?? "", msg: message, sentAt: Date(), attachments: [])
        
        SocketIOManager.shared.sendMessages(room, newMessage)
        chatUIView.sendButton.isEnabled = false
    }

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
            }
            .store(in: &cancellables)
        
        // 키보드 관련
        NotificationCenter.default.publisher(for: UIApplication.keyboardWillShowNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.keyboardWillShow(notification)
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.keyboardWillHideNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.keyboardWillHide(notification)
            }
            .store(in: &cancellables)
    }
    
    private func setUpNotifications() {
        // 방 저장 관련
        NotificationCenter.default.addObserver(self, selector: #selector(handleRoomSaveCompleted), name: .roomSavedComplete, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRoomSaveFailed), name: .roomSaveFailed, object: nil)
    }

//    @objc private func currentRoomObserver(_ notification: Notification) {
//        guard let rooms = notification.userInfo?["rooms"] as? [ChatRoom],
//              let currentRoom = self.room,
//              let updatedCurrentRoom = rooms.first(where: { $0.roomName == currentRoom.roomName }) else { return }
//        
//        DispatchQueue.main.async { [weak self] in
//            guard let self = self else { return }
//            
//            self.room = updatedCurrentRoom
//            self.updateNavigationTitle(with: updatedCurrentRoom)
//            
//            if updatedCurrentRoom.participants.contains(LoginManager.shared.getUserEmail) {
//                self.chatUIView.isHidden = false
//                self.joinRoomBtn.isHidden = true
//            }
//        }
//    }
    
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
    
    private func decideJoinUI() {
        guard let room = room else { return }
        
        if room.participants.contains(LoginManager.shared.getUserEmail) {
            setupChatUI()
            chatUIView.isHidden = false
            joinRoomBtn.isHidden = true
        } else {
            setJoinRoombtn()
        }
        
        updateNavigationTitle(with: room)
    }
    
    private func setJoinRoombtn() {
        self.joinRoomBtn.clipsToBounds = true
        self.joinRoomBtn.layer.cornerRadius = 20
        self.joinRoomBtn.backgroundColor = UIColor(white: 0.1, alpha: 0.05)
        joinRoomBtn.translatesAutoresizingMaskIntoConstraints = false
        
        joinRoomBtn.isHidden = false
        chatUIView.isHidden = true
        
        NSLayoutConstraint.deactivate(chatConstraints)
    
        joinConsraints = [
            chatMessageCollectionView.bottomAnchor.constraint(equalTo: joinRoomBtn.topAnchor)
        ]
        NSLayoutConstraint.activate(joinConsraints)
    }
    

    
    private func updateNavigationTitle(with room: ChatRoom) {
        DispatchQueue.main.async{
            self.navigationItem.setTitle(title: room.roomName, subtitle: "\(room.participants.count)명 참여")
        }
    }
    
    @IBAction func joinRoomBtnTapped(_ sender: UIButton) {
        guard let room = self.room else { return }
        
        FirebaseManager.shared.add_room_participant(room: room)
        SocketIOManager.shared.joinRoom(room.roomName)
        
        setupChatUI()
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
    
    @objc func backButtonTapped() {
        self.navigationController?.popToRootViewController(animated: true)
    }
    
    @objc func swipeAction(_ sender: UISwipeGestureRecognizer) {
        if sender.direction == .right {
            self.navigationController?.popToRootViewController(animated: true)
        }
    }
    
}
