//
//  ChatViewController.swift
//  OutPick
//
//  Created by 김가윤 on 10/14/24.
//

import UIKit
import Combine

class ChatViewController: UIViewController {
    
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
    
    deinit {
        SocketIOManager.shared.closeConnection()
    }
    
    private let optionView: UIView = {
        
        let view = UIView()
        view.backgroundColor = UIColor(white: 0.1, alpha: 0.05)
        view.layer.cornerRadius = 20
        view.isHidden = true

        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 30
        stackView.distribution = .equalSpacing
        stackView.alignment = .center
        
        view.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stackView.heightAnchor.constraint(equalToConstant: 75),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
        ])
        
        for btn in ["photo", "camera", "paperclip"] {
            
            let btn: UIButton = {
                let button = UIButton(type: .system)
                button.setImage(UIImage(systemName: btn), for: .normal)
                button.tintColor = .black
                button.backgroundColor = .white
                
                // 원형으로 만들기 위한 설정
                button.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    button.widthAnchor.constraint(equalToConstant: 50),
                    button.heightAnchor.constraint(equalToConstant: 50)
                ])
                button.layer.cornerRadius = 25 // 반지름 = 너비/2
                button.clipsToBounds = true // 코너가 잘리도록 설정
                
                stackView.addArrangedSubview(button)
                
                return button
            }()
            
        }
        
        return view
    }()
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        let backButton = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: self, action: #selector(backButtonTapped))
        backButton.tintColor = .black
        self.navigationItem.leftBarButtonItem = backButton
        
        if isRoomSaving {
            activityIndicator.startAnimating()
            configureNotifications()
            chatUIStackView.isHidden = false
            joinRoomBtn.isHidden = true
        } else {
            activityIndicator.stopAnimating()
        }
        
        swipeRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(swipeAction(_:)))
        self.view.addGestureRecognizer(swipeRecognizer)

        configureMsgTextView()
        setUpNotifications()
        
        decideJoinUI()
        setUpOptionMenuUI()
        adjustLayoutForSafeArea()
    }
    
    private func adjustLayoutForSafeArea() {
        // 하단 여백 추가
        chatUIStackView.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: view.safeAreaInsets.bottom + 10, right: 0)
        chatUIStackView.isLayoutMarginsRelativeArrangement = true
        
        // 키보드가 올라올 때의 여백 조정
        additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: 10, right: 0)
    }
    
    private func setUpOptionMenuUI() {
        
        self.view.clipsToBounds = false
        view.addSubview(optionView)
        
        optionView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            optionView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            optionView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            optionView.topAnchor.constraint(equalTo: self.chatUIStackView.bottomAnchor, constant: 40),
            optionView.heightAnchor.constraint(equalToConstant: 100),
        ])
        
    }
    
    private func hideOrShowOptionMenu() {
        
        guard let image = attachmentBtn.imageView?.image else { return }

        if image != UIImage(systemName: "xmark") {
            
            attachmentBtn.setImage(UIImage(systemName: "xmark"), for: .normal)
            
            self.msgTextView.resignFirstResponder()
            
            self.optionView.isHidden = false
            self.optionView.alpha = 1
            
            self.optionView.translatesAutoresizingMaskIntoConstraints = true
            self.view.frame.origin.y -= self.optionView.frame.height + 40
            
            
        } else {
            
            attachmentBtn.setImage(UIImage(systemName: "plus"), for: .normal)
            self.optionView.isHidden = true
            self.optionView.alpha = 0
            
            self.optionView.translatesAutoresizingMaskIntoConstraints = true
            self.view.frame.origin.y = .zero
            
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
        
        print("호출: currentRoomObserver")
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
        self.navigationItem.setTitle(title: room.roomName, subtitle: "\(room.participants.count)명 참여")
        
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
            await FirestoreManager.shared.updateRoomParticipants(roomName: room.roomName, email: LoginManager.shared.getUserEmail)
        }
        
    }
    
    @IBAction func sendBtnTapped(_ sender: UIButton) {
        
        guard let message = self.msgTextView.text,
              let roomName = self.room?.roomName else { return }
        self.msgTextView.text = nil
        
        let newMessage = ChatMessage(messageID: UUID().uuidString, senderID: LoginManager.shared.getUserEmail, senderNickname: UserProfile.sharedUserProfile.nickname ?? "", msg: message, sentAt: Date(), messageType: .Text)
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
        
    }
    
    @objc private func keyboardWillShow(_ sender: Notification) {
        guard let keyboardFrame = sender.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let keyboardFrameHeight = keyboardFrame.height
        
        if !self.optionView.isHidden {
            
            self.optionView.isHidden = true
            self.view.frame.origin.y += self.optionView.frame.height + 40
            self.attachmentBtn.setImage(UIImage(systemName: "plus"), for: .normal)
            
        }
        
        if self.view.frame.origin.y == 0 {
            
            self.view.frame.origin.y -= keyboardFrameHeight
            
        }
    }
    
    @objc private func keyboardWillHide() {
        
        if self.view.frame.origin.y != 0 {
            
            self.view.frame.origin.y = .zero
            
        }
        
    }
    
    private func configureMsgTextView() {
        
        self.msgTextView.delegate = self
        msgTextView.text = "메시지를 입력하세요."
        msgTextView.textColor = UIColor.lightGray
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture))
        view.addGestureRecognizer(tapGesture)
        
        self.msgTextView.layer.cornerRadius = 20
        self.msgTextView.clipsToBounds = true
        self.msgTextView.backgroundColor = UIColor(white: 0.1, alpha: 0.05)
        self.msgTextView.alignTextVertically()
        
    }
    
    @objc private func handleTapGesture() {
        msgTextView.resignFirstResponder()
        
        if !self.optionView.isHidden {
            
            attachmentBtn.setImage(UIImage(systemName: "plus"), for: .normal)
            self.optionView.isHidden = true
            self.optionView.alpha = 0
            
            self.optionView.translatesAutoresizingMaskIntoConstraints = true
            DispatchQueue.main.async {
                self.view.frame.origin.y = .zero
            }
            
        }
    }

    private func configureNotifications() {
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleRoomSaveCompleted), name: .roomSavedComplete, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRoomSaveFailed), name: .roomSaveFailed, object: nil)
        
    }
    
    @objc private func handleRoomSaveCompleted(notification: Notification) {
        
        activityIndicator.stopAnimating()
        
        guard let savedRoom = notification.userInfo?["room"] as? ChatRoom,
              let nickName = UserProfile.sharedUserProfile.nickname else { return }
        self.room = savedRoom
        
        Task {
            await FirestoreManager.shared.updateRoomParticipants(roomName: savedRoom.roomName, email: LoginManager.shared.getUserEmail)
        }
        
        SocketIOManager.shared.setUserName(nickName)
        SocketIOManager.shared.createRoom(savedRoom.roomName)
        self.updateNavigationTitle(with: savedRoom)
        
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

extension UINavigationItem {
    
    func setTitle(title: String, subtitle: String) {
        
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 17)
        titleLabel.sizeToFit()
        
        let subTitleLabel = UILabel()
        subTitleLabel.text = subtitle
        subTitleLabel.font = UIFont.systemFont(ofSize: 12)
        subTitleLabel.textAlignment = .center
        subTitleLabel.sizeToFit()
        
        let stackView = UIStackView(arrangedSubviews: [titleLabel, subTitleLabel])
        stackView.distribution = .equalCentering
        stackView.axis = .vertical
        stackView.alignment = .center
        
        let width = max(titleLabel.frame.size.width, subTitleLabel.frame.size.width)
        stackView.frame = CGRect(x: 0, y: 0, width: width, height: 35)
        
        titleLabel.sizeToFit()
        subTitleLabel.sizeToFit()
        
        self.titleView = stackView
    }
    
}

extension UITextView {
    func alignTextVertically() {
        
        var topConstraint = (self.bounds.size.height - (self.contentSize.height)) / 2
        topConstraint = topConstraint < 0.0 ? 0.0 : topConstraint
        self.contentInset.left = 5
        self.contentInset.top = topConstraint
        
    }
    
}

extension ChatViewController: UITextViewDelegate {
    
    func textViewDidBeginEditing(_ textView: UITextView) {
        
        if textView.textColor == .lightGray {
            textView.text = ""
            textView.textColor = .black
        }
        
    }
    
    
    func textViewDidEndEditing(_ textView: UITextView) {
        
        if textView.text.isEmpty {
            textView.text = "메시지를 입력하세요."
            textView.textColor = .lightGray
        }
        
    }
    
    func textViewDidChange(_ textView: UITextView) {
        
        if textView.text.isEmpty {
            sendBtn.isEnabled = false
        } else {
            sendBtn.isEnabled = true
        }
        
    }
    
}
