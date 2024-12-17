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
    
    @IBOutlet weak var chatUIStackView: UIStackView!
    @IBOutlet weak var joinRoomBtn: UIButton!
    
    var swipeRecognizer: UISwipeGestureRecognizer!
    
    private var sideMenuViewController = SideMenuViewController()
    private var dimmingView: UIView?
    
    var room: ChatRoom?
    var isRoomSaving = false
    
    @Published var participants = [String]()
    
    deinit {
        SocketIOManager.shared.closeConnection()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let backButton = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: self, action: #selector(backButtonTapped))
        backButton.tintColor = .black
        self.navigationItem.leftBarButtonItem = backButton
        
        if isRoomSaving {
            activityIndicator.startAnimating()
            configureNotifications()
        } else {
            activityIndicator.stopAnimating()
        }
        
        swipeRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(swipeAction(_:)))
        self.view.addGestureRecognizer(swipeRecognizer)
        
        configureNavigationBarTitle()
        configureMsgTextView()
        setUpKeyboardNotification()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        guard self.room != nil else { return }
        
        DispatchQueue.main.async {
            SocketIOManager.shared.establishConnection {
                guard let roomName = self.room?.roomName else { return }

                SocketIOManager.shared.joinRoom(roomName)
            }
        }
        
        checkJoinedRoom()
    }
    
    private func checkJoinedRoom() {
        let participantsPublisher = FirestoreManager.shared.currentChatRooms.publisher
        
        let _ = participantsPublisher
            .compactMap { $0.participants }
            .tryContains { $0.contains(LoginManager.shared.getUserEmail) }
            .sink(receiveCompletion: { print("completion: \($0)") },
                  receiveValue: {
                if $0 {
                    DispatchQueue.main.async {
                        self.chatUIStackView.isHidden = false
                    }
                } else {
                    DispatchQueue.main.async {
                        self.setJoinRoombtn()
                    }
                }
            } )
    }
    
    private func setJoinRoombtn() {
        self.joinRoomBtn.isHidden = false
        self.joinRoomBtn.clipsToBounds = true
        self.joinRoomBtn.layer.cornerRadius = 20
        self.joinRoomBtn.backgroundColor = UIColor(white: 0.1, alpha: 0.03)
    }
    
    @IBAction func joinRoomBtnTapped(_ sender: UIButton) {
        print("Join The Room!!")
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
    
    private func setUpKeyboardNotification() {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    @objc private func keyboardWillShow(_ sender: Notification) {
        guard let keyboardFrame = sender.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        
        let keyboardFrameHeibht = keyboardFrame.height
        
        if self.view.frame.origin.y == 0 {
            self.view.frame.origin.y -= keyboardFrameHeibht + 10
        }
    }
    
    @objc private func keyboardWillHide() {
        if self.view.frame.origin.y != 0 {
            self.view.frame.origin.y = 0
        }
    }
    
    private func configureMsgTextView() {
        self.msgTextView.delegate = self
        msgTextView.text = "메시지를 입력하세요."
        msgTextView.textColor = UIColor.lightGray
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        view.addGestureRecognizer(tapGesture)
        
        self.msgTextView.layer.cornerRadius = 20
        self.msgTextView.clipsToBounds = true
        self.msgTextView.backgroundColor = UIColor(white: 0.1, alpha: 0.05)
        self.msgTextView.alignTextVertically()
    }
    
    @objc private func dismissKeyboard() {
        msgTextView.resignFirstResponder()
    }
    
    @IBAction func sideMenuBtnTapped(_ sender: UIBarButtonItem) {
        configureSideMenu()
    }
    
    private func configureSideMenu() {
    }
    
    private func configureNavigationBarTitle() {
        guard let roomName = self.room?.roomName,
              let participantsCount = room?.participants.count else { return }
        
        self.navigationItem.setTitle(title: roomName, subtitle: "\(participantsCount)명 참여")
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
        
        SocketIOManager.shared.setUserName(nickName)
        SocketIOManager.shared.createRoom(savedRoom.roomName)
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
