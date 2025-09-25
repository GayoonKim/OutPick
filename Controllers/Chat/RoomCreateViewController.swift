//
//  RoomCreateViewController.swift
//  OutPick
//
//  Created by 김가윤 on 8/5/24.
//

import UIKit
import PhotosUI
import FirebaseFirestore
import Kingfisher
import Combine

class RoomCreateViewController: UIViewController, ChatModalAnimatable {
    
    @IBOutlet weak var roomNameTextView: UITextView!
    @IBOutlet weak var roomNameCountLabel: UILabel!
    @IBOutlet weak var roomDescriptionTextView: UITextView!
    @IBOutlet weak var roomDescriptionCountLabel: UILabel!
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var scrollViewTopConstraint: NSLayoutConstraint!
    
    @IBOutlet weak var roomImageView: UIImageView!
    
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    
    var roomInfo: ChatRoom?
    private var isDefaultRoomImage = true
    
    private lazy var createBtn: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("생성", for: .normal)
        button.setTitleColor(.lightGray, for: .disabled)
        button.setTitleColor(.black, for: .normal)
        button.isEnabled = false
        button.clipsToBounds = true
        button.backgroundColor = UIColor(white: 0.1, alpha: 0.05)
        button.accessibilityIdentifier = "sendButton"
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(handleCreateButtonTap), for: .touchUpInside)
        
        return button
    }()
    
    private lazy var customNavigationBar: CustomNavigationBarView = {
        let navBar = CustomNavigationBarView()
        navBar.translatesAutoresizingMaskIntoConstraints = false
        
        return navBar
    }()
    
    private lazy var cancellables: Set<AnyCancellable> = []
    
    let maxHeight: CGFloat = 300
    
    let removeImageButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "minus.circle.fill"), for: .normal)
        button.tintColor = .red
        
        return button
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
//        self.attachInteractiveDismissGesture()
        
        setupCustomNavigationBar()
        setupTextView(roomNameTextView)
        setupTextView(roomDescriptionTextView)
        addImageButtonSetup()
        setupCreateButton()

        self.roomImageView.clipsToBounds = true
        self.roomImageView.layer.cornerRadius = 15
        
        self.bindPublishers()
    }

    private func bindPublishers() {
        // 키보드 관련
        NotificationCenter.default.publisher(for: UIApplication.keyboardWillShowNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.keyboardWillShow(notification: notification)
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.keyboardWillHideNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.keyboardWillHide(notification: notification)
            }
            .store(in: &cancellables)
    }
    
    private func setupCreateButton() {
        view.addSubview(createBtn)
        createBtn.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            createBtn.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            createBtn.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            createBtn.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            createBtn.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    @MainActor
    @objc func handleCreateButtonTap() {
        self.createBtn.isEnabled = false
        LoadingIndicator.shared.start(on: self)
        
        Task {
            do {
                if try await FirebaseManager.shared.checkDuplicate(strToCompare: self.roomNameTextView.text, fieldToCompare: "roomName", collectionName: "Rooms") {
                        LoadingIndicator.shared.stop()
                        createBtn.isEnabled = true
                        AlertManager.showAlertNoHandler(title: "중복된 방 이름", message: "이미 존재하는 방 이름입니다. 다른 이름을 선택해 주세요.", viewController: self)
                    return
                }
                
                let ref = Firestore.firestore().collection("Rooms").document()
                let room = ChatRoom(ID: ref.documentID, roomName: self.roomNameTextView.text, roomDescription: self.roomDescriptionTextView.text, participants: [LoginManager.shared.getUserEmail], creatorID: LoginManager.shared.getUserEmail, createdAt: Date(), roomImagePath: nil)

                let storyboard = UIStoryboard(name: "Main", bundle: nil)
                guard let chatRoomVC = storyboard.instantiateViewController(withIdentifier: "chatRoomVC") as? ChatViewController else { return }
                chatRoomVC.room = room
                chatRoomVC.isRoomSaving = true
                chatRoomVC.modalPresentationStyle = .fullScreen

                ChatModalTransitionManager.present(chatRoomVC, from: self)

                self.saveRoomInfo(room: room)
                
            } catch {
                    LoadingIndicator.shared.stop()
                    AlertManager.showAlertNoHandler(title: "오류", message: "방 생성 중 오류가 발생했습니다.", viewController: self)
            }
        }
        
    }
    
    private func setupTextView(_ textView: UITextView) {
        textView.delegate = self
        textView.clipsToBounds = true
        textView.layer.cornerRadius = 10
        textView.backgroundColor = UIColor(white: 0.1, alpha: 0.03)
        textView.font = UIFont.preferredFont(forTextStyle: .headline)
        textView.font = UIFont.systemFont(ofSize: 15)
    }
    
    private func addImageButtonSetup() {
        let addImageButton: UIButton = {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: "plus.circle.fill"), for: .normal)
            button.addTarget(self, action: #selector(addImageButtonTapped), for: .touchUpInside)
            
            return button
        }()
        
        view.addSubview(addImageButton)
        
        addImageButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            addImageButton.centerXAnchor.constraint(equalTo: roomImageView.trailingAnchor),
            addImageButton.centerYAnchor.constraint(equalTo: roomImageView.bottomAnchor),
            addImageButton.widthAnchor.constraint(equalToConstant: 30),
            addImageButton.heightAnchor.constraint(equalToConstant: 30)
        ])
    }
    
    @objc private func addImageButtonTapped() {
        let alertController = UIAlertController(title: "사진 추가 ", message: "사진을 선택하거나 촬영하세요", preferredStyle: .actionSheet)
        
        alertController.addAction(UIAlertAction(title: "앨범", style: .default, handler: { _ in
            self.openPhotoLibrary()
        }))
        
        alertController.addAction(UIAlertAction(title: "카메라", style: .default, handler: { _ in
            self.openCamera()
        }))
        
        alertController.addAction(UIAlertAction(title: "취소", style: .cancel, handler: nil))
        
        present(alertController, animated: true, completion: nil)
    }
    
    private func openPhotoLibrary() {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images // 이미지만 선택 가능하도록 설정
        config.selectionLimit = 1 // 선택 가능한 최대 이미지 수
        config.preferredAssetRepresentationMode = .current
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        
        present(picker, animated: true, completion: nil)
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

    private func removeImageButtonSetup() {
        view.addSubview(removeImageButton)
        removeImageButton.addTarget(self, action: #selector(removeImageButtonTapped(_:)), for: .touchUpInside)
        
        removeImageButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            removeImageButton.centerXAnchor.constraint(equalTo: roomImageView.leadingAnchor),
            removeImageButton.centerYAnchor.constraint(equalTo: roomImageView.bottomAnchor),
            removeImageButton.widthAnchor.constraint(equalToConstant: 30),
            removeImageButton.heightAnchor.constraint(equalToConstant: 30)
        ])

    }
    
    @objc private func removeImageButtonTapped(_ sender: UIButton) {
        roomImageView.image = UIImage(named: "Default_Profile")
        roomImageView.accessibilityIdentifier = "Default_Profile"
        isDefaultRoomImage = true
        sender.isHidden = true
    }

    private func saveRoomInfo(room: ChatRoom) {
        if let image = roomImageView.image {
            if !isDefaultRoomImage {
                uploadImageAndSaveRoomInfo(image: image, roomInfo: room)
            } else {
                saveRoomInfoToFirestore(room: room, image: nil)
            }
        }
    }
    
    private func uploadImageAndSaveRoomInfo(image: UIImage, roomInfo: ChatRoom) {
        Task {
            do {
                let imagePath = try await FirebaseStorageManager.shared.uploadImageToStorage(image: image, location: ImageLocation.RoomImage, roomName: roomInfo.roomName)
                
                var updatedRoomInfo = roomInfo
                updatedRoomInfo.roomImagePath = imagePath
                
                self.saveRoomInfoToFirestore(room: updatedRoomInfo, image: image)
            } catch {
                NotificationCenter.default.post(name: .roomSaveFailed, object: nil, userInfo: ["error": RoomCreationError.imageUploadFailed])
            }
        }
    }
    
    private func saveRoomInfoToFirestore(room: ChatRoom, image: UIImage?) {
        FirebaseManager.shared.saveRoomInfoToFirestore(room: room) { result in
            switch result {
            case .success:
                if let imagePath = room.roomImagePath, let image = image {
                    KingfisherManager.shared.cache.store(image, forKey: imagePath)
                }
                NotificationCenter.default.post(name: .roomSavedComplete, object: nil, userInfo: ["room": room])
            case .failure:
                NotificationCenter.default.post(name: .roomSaveFailed, object: nil, userInfo: ["error": RoomCreationError.saveFailed])
            }
        }
    }
    
    private func enableCreateBtn() {
        if !roomNameTextView.text.isEmpty && !roomDescriptionTextView.text.isEmpty {
            createBtn.isEnabled = true
        } else {
            createBtn.isEnabled = false
        }
    }

    @objc func keyboardWillShow(notification: Notification) {
        guard roomDescriptionTextView.isFirstResponder,
              let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        
        let labelFrame = roomDescriptionCountLabel.convert(roomDescriptionCountLabel.bounds, to: view)
        
        // 겹치는지 확인
        if labelFrame.intersects(keyboardFrame) {
            let keyboardHeight = keyboardFrame.height
            let contentInsets = UIEdgeInsets(top: 0, left: 0, bottom: keyboardHeight, right: 0)
            
            scrollView.contentInset = contentInsets
            scrollView.scrollIndicatorInsets = contentInsets
            
            // 커서 위치가 키보드 위로 올라오도록 스크롤
            scrollView.scrollRectToVisible(labelFrame, animated: true)
        }
    }
    
    @objc func keyboardWillHide(notification: Notification) {
        // 키보드 내려가면 초기화
        let contentInsets = UIEdgeInsets.zero
        scrollView.contentInset = contentInsets
        scrollView.scrollIndicatorInsets = contentInsets
    }
    
}

extension RoomCreateViewController: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let currentText = textView.text ?? ""
        
        guard let stringRange = Range(range, in: currentText) else { return false }
        
        let updatedText = currentText.replacingCharacters(in: stringRange, with: text)
        
        if text == "\n" {
            textView.resignFirstResponder() // 키보드 숨기기
            return false // 엔터 키 입력 방지
        }
        
        switch textView {
        case roomNameTextView:
            return updatedText.count <= 20
        case roomDescriptionTextView:
            return updatedText.count <= 200
        default:
            break
        }
        
//        return updatedText.count <= 20
        return false
    }
    
    func textViewDidChange(_ textView: UITextView) {
        guard let text = textView.text else { return }
        
        switch textView {
        case roomNameTextView:
            roomNameCountLabel.text = "\(text.count) / 20"
        case roomDescriptionTextView:
            roomDescriptionCountLabel.text = "\(text.count) / 200"
        default:
            break
        }
        
        if !roomNameTextView.text.isEmpty && !roomDescriptionTextView.text.isEmpty {
            enableCreateBtn()
        }
    }
}

extension Notification.Name {
    static let roomSavedComplete = Notification.Name("roomSaveCompleted")
    static let roomSaveFailed = Notification.Name("roomSaveFailed")
}

extension RoomCreateViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true, completion: nil)
        
        Task {
            let image = try await MediaManager.shared.convertImage(results.first!)
            
            DispatchQueue.main.async {
                
                self.roomImageView.image = image
                self.roomImageView.accessibilityIdentifier = "Custom_Image"
                self.isDefaultRoomImage = false
                
                self.removeImageButtonSetup()
                
            }
        }
    }
}

extension RoomCreateViewController: UIImagePickerControllerDelegate & UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        if let selectedImage = info[.originalImage] as? UIImage,
           let cgImage = MediaManager.compressImageWithImageIO(selectedImage) {
            self.roomImageView.image = UIImage(cgImage: cgImage)
            self.roomImageView.accessibilityIdentifier = "Custom_Image"
            self.removeImageButtonSetup()
            self.enableCreateBtn()
        } else if let editedImage = info[.editedImage] as? UIImage,
                  let cgImage = MediaManager.compressImageWithImageIO(editedImage) {
            self.roomImageView.image = UIImage(cgImage: cgImage)
            self.roomImageView.accessibilityIdentifier = "Custom_Image"
            self.removeImageButtonSetup()
            self.enableCreateBtn()
        }
        
        picker.dismiss(animated: true, completion: nil)
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }
    
    @objc func cancelButtonTapped() {
        let alert = UIAlertController(title: "채팅방 개설을 취소하시겠어요?", message: nil, preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "계속 작성하기", style: .default, handler: nil))
        alert.addAction(UIAlertAction(title: "개설 취소하기", style: .destructive, handler:  { _ in
            ChatModalTransitionManager.dismiss(from: self)
        }))
        
        self.present(alert, animated: true, completion: nil)
        }
}

private extension RoomCreateViewController {
    @MainActor
    func setupCustomNavigationBar() {
        self.view.addSubview(customNavigationBar)
        self.scrollView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            customNavigationBar.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            customNavigationBar.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            customNavigationBar.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
        ])
        
        scrollViewTopConstraint.isActive = false
        scrollView.topAnchor.constraint(equalTo: customNavigationBar.bottomAnchor).isActive = true
        
        customNavigationBar.configureForRoomCreate(target: self, onBack: #selector(cancelButtonTapped))
    }
}
