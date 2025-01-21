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
    @IBOutlet weak var msgTextView: UITextView!
    @IBOutlet weak var sendBtn: UIButton!
    @IBOutlet weak var attachmentBtn: UIButton!
    
    @IBOutlet weak var chatUIStackView: UIStackView!
    
    @IBOutlet weak var joinRoomBtn: UIButton!
    
    var swipeRecognizer: UISwipeGestureRecognizer!
    
    private var sideMenuViewController = SideMenuViewController()
    private var dimmingView: UIView?
    
    var room: ChatRoom?
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
        view.delegate = self
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
//    private lazy var optionView: UIView = {
//        
//        let optionView = UIView()
//        optionView.backgroundColor = UIColor(white: 0.1, alpha: 0.05)
//        optionView.layer.cornerRadius = 20
//        optionView.isHidden = true
//        optionView.tag = 98
//        
//        let stackView = UIStackView()
//        stackView.axis = .horizontal
//        stackView.spacing = 30
//        stackView.distribution = .equalSpacing
//        stackView.alignment = .center
//        stackView.tag = 99
//        
//        for btn in ["photo", "camera", "paperclip"] {
//            
//            let button = UIButton(type: .system)
//            button.setImage(UIImage(systemName: btn), for: .normal)
//            button.tintColor = .black
//            button.backgroundColor = .white
//            button.accessibilityIdentifier = btn
//            button.addTarget(self, action: #selector(checkAttachmentBtnKind(_:)), for: .touchUpInside)
//            
//            // 원형으로 만들기 위한 설정
//            button.translatesAutoresizingMaskIntoConstraints = false
//            NSLayoutConstraint.activate([
//                button.widthAnchor.constraint(equalToConstant: 50),
//                button.heightAnchor.constraint(equalToConstant: 50)
//            ])
//            button.layer.cornerRadius = 25 // 반지름 = 너비/2
//            button.clipsToBounds = true // 코너가 잘리도록 설정
//            
//            stackView.addArrangedSubview(button)
//            
//        }
//        
//        optionView.addSubview(stackView)
//        
//        stackView.translatesAutoresizingMaskIntoConstraints = false
//        NSLayoutConstraint.activate([
//            stackView.centerXAnchor.constraint(equalTo: optionView.centerXAnchor),
//            stackView.centerYAnchor.constraint(equalTo: optionView.centerYAnchor),
//            stackView.heightAnchor.constraint(equalToConstant: 75),
//            stackView.leadingAnchor.constraint(equalTo: optionView.leadingAnchor, constant: 40),
//            stackView.trailingAnchor.constraint(equalTo: optionView.trailingAnchor, constant: -40),
//        ])
//        
//        return optionView
//    }()
    
    private var preselectedIdentifiers: [String] = []
    private var selectedImages: [UIImage] = []
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        let backButton = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: self, action: #selector(backButtonTapped))
        backButton.tintColor = .black
        self.navigationItem.leftBarButtonItem = backButton
        
        setUpNotifications()
        
        if isRoomSaving {
            activityIndicator.startAnimating()
            //            configureNotifications()
            chatUIStackView.isHidden = false
            joinRoomBtn.isHidden = true
        } else {
            activityIndicator.stopAnimating()
        }
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture))
        tapGesture.delegate = self
        view.addGestureRecognizer(tapGesture)
        
        swipeRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(swipeAction(_:)))
        self.view.addGestureRecognizer(swipeRecognizer)
        
        configureMsgTextView()
        decideJoinUI()
        setUpOptionMenuUI()
        adjustLayoutForSafeArea()
        
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
        configuration.preselectedAssetIdentifiers = preselectedIdentifiers
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
        
    }
    
    private func adjustLayoutForSafeArea() {
        
        // 하단 여백 추가
        chatUIStackView.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: view.safeAreaInsets.bottom + 10, right: 0)
        chatUIStackView.isLayoutMarginsRelativeArrangement = true
        
    }
    
    private func setUpOptionMenuUI() {
        
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
            
            if self.msgTextView.isFirstResponder {
                
                self.msgTextView.resignFirstResponder()
                
            }
            
            self.attachmentView.isHidden = false
            self.attachmentView.alpha = 1
            
            self.chatUIStackView.translatesAutoresizingMaskIntoConstraints = true
            self.chatUIStackView.frame.origin.y -= self.attachmentView.frame.height
            
        } else {
            
            self.attachmentBtn.setImage(UIImage(systemName: "plus"), for: .normal)
            self.attachmentView.isHidden = true
            self.attachmentView.alpha = 0
            
            self.chatUIStackView.translatesAutoresizingMaskIntoConstraints = true
            self.chatUIStackView.frame.origin.y += self.attachmentView.frame.height
            
        }
        
    }
    
    @IBAction func attachmentBtnTapped(_ sender: UIButton) {
        self.hideOrShowOptionMenu()
    }
    
    private func decideJoinUI() {
        
        guard let room = room else { return }
        
        if room.participants.contains(LoginManager.shared.getUserEmail) {
            chatUIStackView.isHidden = false
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
                self.chatUIStackView.isHidden = false
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
        
        Task {
            try await FirebaseManager.shared.updateRoomParticipant(room: room, isAdding: true)
        }
        
    }
    
    @IBAction func sendBtnTapped(_ sender: UIButton) {
        
        guard let message = self.msgTextView.text,
              let roomName = self.room?.roomName else { return }
        self.msgTextView.text = nil
        
        let newMessage = ChatMessage(senderID: LoginManager.shared.getUserEmail, senderNickname: UserProfile.shared.nickname ?? "", msg: message, sentAt: Date(), messageType: .Text)
        print(newMessage)
        
        SocketIOManager.shared.sendMessage(roomName, message)
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
            self.chatUIStackView.frame.origin.y += self.attachmentView.frame.height
            
        }
        
        if keyboardFrame.intersects(self.chatUIStackView.frame) {
            
            self.chatUIStackView.translatesAutoresizingMaskIntoConstraints = true
            let safeAreaBottom = self.view.safeAreaInsets.bottom
            self.chatUIStackView.frame.origin.y -= (keyboardFrameHeight - safeAreaBottom) + 5
            
        }
        
    }
    
    @objc private func keyboardWillHide(_ sender: Notification) {
        
        guard let keyboardFrame = sender.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let keyboardFrameHeight = keyboardFrame.height
        
        if self.chatUIStackView.frame.origin.y != 0 {
            
            let safeAreaBottom = self.view.safeAreaInsets.bottom
            self.chatUIStackView.frame.origin.y += (keyboardFrameHeight - safeAreaBottom) + 5
            
        }
        
    }
    
    private func configureMsgTextView() {
        
        self.msgTextView.delegate = self
        msgTextView.text = "메시지를 입력하세요."
        msgTextView.textColor = UIColor.lightGray
        
        self.msgTextView.layer.cornerRadius = 20
        self.msgTextView.clipsToBounds = true
        self.msgTextView.backgroundColor = UIColor(white: 0.1, alpha: 0.05)
        self.msgTextView.alignTextVertically()
        
    }
    
    @objc private func handleTapGesture() {
        
        msgTextView.resignFirstResponder()
        
        if !self.attachmentView.isHidden {
            
            attachmentBtn.setImage(UIImage(systemName: "plus"), for: .normal)
            self.attachmentView.isHidden = true
            self.attachmentView.alpha = 0
            
            self.attachmentView.translatesAutoresizingMaskIntoConstraints = true
            self.chatUIStackView.frame.origin.y += self.attachmentView.frame.height
            
        }
        
    }
    
    @objc private func handleRoomSaveCompleted(notification: Notification) {
        
        DispatchQueue.main.async {
            self.activityIndicator.stopAnimating()
        }
        
        guard let savedRoom = notification.userInfo?["room"] as? ChatRoom else { return }
        self.room = savedRoom

        DispatchQueue.main.async {
            self.updateNavigationTitle(with: savedRoom)
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

extension ChatViewController: AttachmentViewDelegate {
    
    internal func checkAttachmentBtnKind(didTapBtnWith identifier: String) {
        switch identifier {
            
        case "photo":
            print("Photo btn tapped!")
            self.hideOrShowOptionMenu()
            self.openPHPicker()
            
        case "camera":
            print("Camera btn tapped!")
            self.hideOrShowOptionMenu()
            self.openCamera()
            
        case "paperclip":
            print("File btn tapped!")
            
        default:
            return
            
        }
    }
    
}
