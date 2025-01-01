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
    
    private lazy var optionView: UIView = {
        
        let optionView = UIView()
        optionView.backgroundColor = UIColor(white: 0.1, alpha: 0.05)
        optionView.layer.cornerRadius = 20
        optionView.isHidden = true
        optionView.tag = 99

        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 30
        stackView.distribution = .equalSpacing
        stackView.alignment = .center
        
        for btn in ["photo", "camera", "paperclip"] {
            
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: btn), for: .normal)
            button.tintColor = .black
            button.backgroundColor = .red
            button.accessibilityIdentifier = btn
            button.addTarget(self, action: #selector(checkAttachmentButtonKind), for: .touchUpInside)
            
            // 원형으로 만들기 위한 설정
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 50),
                button.heightAnchor.constraint(equalToConstant: 50)
            ])
            button.layer.cornerRadius = 25 // 반지름 = 너비/2
            button.clipsToBounds = true // 코너가 잘리도록 설정
            
            stackView.addArrangedSubview(button)
            
        }
        
        optionView.addSubview(stackView)
        
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: optionView.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: optionView.centerYAnchor),
            stackView.heightAnchor.constraint(equalToConstant: 75),
            stackView.leadingAnchor.constraint(equalTo: optionView.leadingAnchor, constant: 40),
            stackView.trailingAnchor.constraint(equalTo: optionView.trailingAnchor, constant: -40),
        ])

        return optionView
    }()
    
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
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
        
        swipeRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(swipeAction(_:)))
        self.view.addGestureRecognizer(swipeRecognizer)

        configureMsgTextView()
        decideJoinUI()
        setUpOptionMenuUI()
        adjustLayoutForSafeArea()
        
    }
    
    @objc func checkAttachmentButtonKind() {
        print("Button tapped!") // 이 코드로 메서드 호출 여부 확인
        
    }
    
    private func adjustLayoutForSafeArea() {
        
        // 하단 여백 추가
        chatUIStackView.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: view.safeAreaInsets.bottom + 10, right: 0)
        chatUIStackView.isLayoutMarginsRelativeArrangement = true
    
    }
    
    private func setUpOptionMenuUI() {
        
        self.view.addSubview(optionView)
        optionView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            optionView.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor),
            optionView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            optionView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            optionView.heightAnchor.constraint(equalToConstant: 100),
        ])
        
    }
    
    private func hideOrShowOptionMenu() {
        
        guard let image = attachmentBtn.imageView?.image else { return }

        if image != UIImage(systemName: "xmark") {
            
            attachmentBtn.setImage(UIImage(systemName: "xmark"), for: .normal)
            
            if msgTextView.isFirstResponder {
                
                self.msgTextView.resignFirstResponder()
                
            }
            
            self.optionView.isHidden = false
            self.optionView.alpha = 1
            
            self.chatUIStackView.translatesAutoresizingMaskIntoConstraints = true
            self.chatUIStackView.frame.origin.y -= self.optionView.frame.height
            
        } else {
            
            attachmentBtn.setImage(UIImage(systemName: "plus"), for: .normal)
            self.optionView.isHidden = true
            self.optionView.alpha = 0
            
            self.chatUIStackView.translatesAutoresizingMaskIntoConstraints = true
            self.chatUIStackView.frame.origin.y += self.optionView.frame.height
            
        }
        
    }
    
    @IBAction func attachmentBtnTapped(_ sender: UIButton) {
        print("첨부 파일 버튼 클릭")
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
        
        // 방 저장 관련
        NotificationCenter.default.addObserver(self, selector: #selector(handleRoomSaveCompleted), name: .roomSavedComplete, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRoomSaveFailed), name: .roomSaveFailed, object: nil)
        
    }
    
    @objc private func keyboardWillShow(_ sender: Notification) {
        
        guard let keyboardFrame = sender.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let keyboardFrameHeight = keyboardFrame.height
        
        if !optionView.isHidden {
            
            self.optionView.isHidden = true
            self.attachmentBtn.setImage(UIImage(systemName: "plus"), for: .normal)
            self.chatUIStackView.frame.origin.y += self.optionView.frame.height
            
        }
        
        if keyboardFrame.intersects(self.chatUIStackView.frame) {
            
            self.chatUIStackView.frame.origin.y -= keyboardFrameHeight - 30
            
        }
    }
    
    @objc private func keyboardWillHide(_ sender: Notification) {
        
        guard let keyboardFrame = sender.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let keyboardFrameHeight = keyboardFrame.height
        
        if self.chatUIStackView.frame.origin.y != 0 {
            
            self.chatUIStackView.frame.origin.y += keyboardFrameHeight - 30
            
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

        if !self.optionView.isHidden {
            
            attachmentBtn.setImage(UIImage(systemName: "plus"), for: .normal)
            self.optionView.isHidden = true
            self.optionView.alpha = 0
            
            self.optionView.translatesAutoresizingMaskIntoConstraints = true
            self.chatUIStackView.frame.origin.y += self.optionView.frame.height
            
        }
        
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
        
//        let size = self.sizeThatFits(CGSize(width: self.frame.width, height: CGFloat.greatestFiniteMagnitude))
//        var topCorrection = (self.bounds.size.height - size.height * self.zoomScale) / 2.0
//        topCorrection = max(0, topCorrection)
//        self.contentInset.top = topCorrection
        
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
        
        textView.alignTextVertically()
        
    }
    
}

extension ChatViewController: UIGestureRecognizerDelegate {
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        
        // 터치된 뷰가 UIButton일 경우 제스처 제외
        if let touchedView = touch.view, touchedView is UIButton {
            return false
        }
        
        return true
        
    }
    
}
