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
            self?.handleAttachmentButtonTap(identifier: identifier)
        }
        
        return view
    }()
    
    private lazy var chatUIView: ChatUIView = {
        let view = ChatUIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    private lazy var cancellables = Set<AnyCancellable>()
    private lazy var chatMessageCollectionView = ChatMessageCollectionView()
    
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
        
        setupChatUI()
        setupAttachmentView()
        decideJoinUI()
        
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
    
    private func setupChatUI() {
        view.addSubview(chatMessageCollectionView)
        self.view.addSubview(self.chatUIView)
        
        chatMessageCollectionView.translatesAutoresizingMaskIntoConstraints = false
        chatUIView.translatesAutoresizingMaskIntoConstraints = false
        self.chatUIView.isHidden = true
        
        NSLayoutConstraint.activate([
            self.chatUIView.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            self.chatUIView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 8),
            self.chatUIView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -8),
            self.chatUIView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            
            chatMessageCollectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            chatMessageCollectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chatMessageCollectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chatMessageCollectionView.bottomAnchor.constraint(equalTo: chatUIView.topAnchor, constant: -8)
        ])
    }
    
    
    private func setupChatMessageCollectionView() {
        chatMessageCollectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(chatMessageCollectionView)
        
        NSLayoutConstraint.activate([
            chatMessageCollectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            chatMessageCollectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chatMessageCollectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chatMessageCollectionView.bottomAnchor.constraint(equalTo: chatUIView.topAnchor, constant: -8)
            ])
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

        default:
            return
        }
    }
    
    private func bindPublishers() {
        SocketIOManager.shared.receivedMessagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] receivedMessage in
                guard let self = self else { return }
                
                print("메시지 수신 성공: \(receivedMessage)")
                chatMessageCollectionView.addMessages(with: receivedMessage)
            }
            .store(in: &cancellables)
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
    
//    private func adjustLayoutForSafeArea() {
//        // 하단 여백 추가
//        chatUIStackView.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: view.safeAreaInsets.bottom + 10, right: 0)
//        chatUIStackView.isLayoutMarginsRelativeArrangement = true
//    }
    
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
    
    private func hideOrShowOptionMenu() {
        guard let image = self.attachmentBtn.imageView?.image else { return }
        if image != UIImage(systemName: "xmark") {

            self.attachmentBtn.setImage(UIImage(systemName: "xmark"), for: .normal)
            
            if self.chatUIView.textView.isFirstResponder {
                self.chatUIView.textView.resignFirstResponder()
            }
            
            self.attachmentView.isHidden = false
            self.attachmentView.alpha = 1
            
            self.chatUIView.translatesAutoresizingMaskIntoConstraints = true
            self.chatUIView.frame.origin.y -= self.attachmentView.frame.height
        } else {
            self.attachmentBtn.setImage(UIImage(systemName: "plus"), for: .normal)
            self.attachmentView.isHidden = true
            self.attachmentView.alpha = 0
            
            self.chatUIView.translatesAutoresizingMaskIntoConstraints = true
            self.chatUIView.frame.origin.y += self.attachmentView.frame.height
            
        }
    }
    
    @IBAction func attachmentBtnTapped(_ sender: UIButton) {
        self.hideOrShowOptionMenu()
    }
    
    private func decideJoinUI() {
        guard let room = room else { return }
        
        if room.participants.contains(LoginManager.shared.getUserEmail) {
            chatUIView.isHidden = false
        } else {
            setJoinRoombtn()
        }
        
        updateNavigationTitle(with: room)
    }
    
    @objc private func currentRoomObserver(_ notification: Notification) {
        guard let rooms = notification.userInfo?["rooms"] as? [ChatRoom],
              let currentRoom = self.room,
              let updatedCurrentRoom = rooms.first(where: { $0.roomName == currentRoom.roomName }) else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.room = updatedCurrentRoom
            self.updateNavigationTitle(with: updatedCurrentRoom)
            
            if updatedCurrentRoom.participants.contains(LoginManager.shared.getUserEmail) {
                self.chatUIView.isHidden = false
                self.joinRoomBtn.isHidden = true
            }
        }
    }
    
    private func updateNavigationTitle(with room: ChatRoom) {
        DispatchQueue.main.async{
            self.navigationItem.setTitle(title: room.roomName, subtitle: "\(room.participants.count)명 참여")
        }
    }
    
    private func setJoinRoombtn() {
        self.joinRoomBtn.isHidden = false
        self.joinRoomBtn.clipsToBounds = true
        self.joinRoomBtn.layer.cornerRadius = 20
        self.joinRoomBtn.backgroundColor = UIColor(white: 0.1, alpha: 0.05)
    }
    
    @IBAction func joinRoomBtnTapped(_ sender: UIButton) {
        guard let room = self.room else { return }
        
        FirebaseManager.shared.add_room_participant(room: room)
        SocketIOManager.shared.joinRoom(room.roomName)
    }
    
    @IBAction func sendBtnTapped(_ sender: UIButton) {
        guard let message = self.chatUIView.textView.text,
              let room = self.room else { return }
        self.chatUIView.textView.text = nil
        
        let newMessage = ChatMessage(roomName: room.roomName,senderID: LoginManager.shared.getUserEmail, senderNickname: UserProfile.shared.nickname ?? "", msg: message, sentAt: Date(), attachments: nil)
        
        SocketIOManager.shared.sendMessages(room, newMessage)
        sendBtn.isEnabled = false
    }
    
    private func setUpNotifications() {
        // 키보드 관련
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
        
        // 실시간 방 업데이트 관련
        NotificationCenter.default.addObserver(self, selector: #selector(currentRoomObserver), name: .chatRoomsUpdated, object: nil)
        
        // 방 저장 관련
        NotificationCenter.default.addObserver(self, selector: #selector(handleRoomSaveCompleted), name: .roomSavedComplete, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRoomSaveFailed), name: .roomSaveFailed, object: nil)
    }
    
    @objc private func keyboardWillShow(_ sender: Notification) {
        
        guard let keyboardFrame = sender.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let keyboardFrameHeight = keyboardFrame.height
        
        if !self.attachmentView.isHidden {
            
            self.attachmentView.isHidden = true
            self.attachmentBtn.setImage(UIImage(systemName: "plus"), for: .normal)
//            self.chatUIStackView.frame.origin.y += self.attachmentView.frame.height
            self.chatUIView.frame.origin.y += self.attachmentView.frame.height
            
        }
        
        /*if keyboardFrame.intersects(self.chatUIStackView.frame)*/ if keyboardFrame.intersects(self.chatUIView.frame) {
            
//            self.chatUIStackView.translatesAutoresizingMaskIntoConstraints = true
            self.chatUIView.translatesAutoresizingMaskIntoConstraints = true
            let safeAreaBottom = self.view.safeAreaInsets.bottom
//            self.chatUIStackView.frame.origin.y -= (keyboardFrameHeight - safeAreaBottom) + 5
            self.chatUIView.frame.origin.y -= (keyboardFrameHeight - safeAreaBottom) + 5
            
        }
        
    }
    
    @objc private func keyboardWillHide(_ sender: Notification) {
        
        guard let keyboardFrame = sender.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let keyboardFrameHeight = keyboardFrame.height
        
        if self.chatUIView.frame.origin.y != 0 {
            
            let safeAreaBottom = self.view.safeAreaInsets.bottom
//            self.chatUIStackView.frame.origin.y += (keyboardFrameHeight - safeAreaBottom) + 5
            self.chatUIView.frame.origin.y += (keyboardFrameHeight - safeAreaBottom) + 5
            
        }
        
    }
    
//    private func configureMsgTextView() {
//        
////        self.msgTextView.delegate = self
//        msgTextView.text = "메시지를 입력하세요."
//        msgTextView.textColor = UIColor.lightGray
//        
//        self.msgTextView.translatesAutoresizingMaskIntoConstraints = false
//        self.msgTextView.isScrollEnabled = false
//        NSLayoutConstraint.activate([
//            self.msgTextView.heightAnchor.constraint(equalToConstant: 44)
//        ])
//        self.msgTextView.layer.cornerRadius = 20
//        self.msgTextView.clipsToBounds = true
//        self.msgTextView.backgroundColor = UIColor(white: 0.1, alpha: 0.05)
//        self.msgTextView.alignTextVertically()
//        
//    }
    
    @objc private func handleTapGesture() {
//        msgTextView.resignFirstResponder()
        chatUIView.textView.resignFirstResponder()
        
        if !self.attachmentView.isHidden {
            
            attachmentBtn.setImage(UIImage(systemName: "plus"), for: .normal)
            self.attachmentView.isHidden = true
            self.attachmentView.alpha = 0
            
            self.attachmentView.translatesAutoresizingMaskIntoConstraints = true
//            self.chatUIStackView.frame.origin.y += self.attachmentView.frame.height
            self.chatUIView.frame.origin.y += self.attachmentView.frame.height
            
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
