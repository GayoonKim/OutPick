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

class RoomCreateViewController: UIViewController, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate & UINavigationControllerDelegate {
    
    @IBOutlet weak var roomNameTextView: UITextView!
    @IBOutlet weak var roomNameCountLabel: UILabel!
    @IBOutlet weak var roomDescriptionTextView: UITextView!
    @IBOutlet weak var roomDescriptionCountLabel: UILabel!
    @IBOutlet weak var createButton: UIButton!
    @IBOutlet weak var scrollView: UIScrollView!
    
    @IBOutlet weak var roomImageView: UIImageView!
    
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    
    var roomInfo: ChatRoom?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupTextView(roomNameTextView)
        setupTextView(roomDescriptionTextView)
        addImageButtonSetup()
        setCreateButton(createButton)

        let backButton = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: self, action: #selector(backButtonTapped))
        backButton.tintColor = .black
        self.navigationItem.leftBarButtonItem = backButton
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
        
        self.roomImageView.clipsToBounds = true
        self.roomImageView.layer.cornerRadius = 15
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    @objc func backButtonTapped() {
        let alert = UIAlertController(title: "채팅방 개설을 취소하시겠어요?", message: nil, preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "계속 작성", style: .default, handler: nil))
        alert.addAction(UIAlertAction(title: "취소", style: .destructive, handler:  { _ in
            self.navigationController?.popViewController(animated: true)
        }))
        
        self.present(alert, animated: true, completion: nil)
        }
    
    
    private func setupTextView(_ textView: UITextView) {
        textView.delegate = self
        textView.clipsToBounds = true
        textView.layer.cornerRadius = 10
        textView.backgroundColor = UIColor(white: 0.1, alpha: 0.03)
        textView.font = UIFont.preferredFont(forTextStyle: .headline)
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
    
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true, completion: nil)
        
        guard let itemProvider = results.first?.itemProvider else { return }
        
        if itemProvider.canLoadObject(ofClass: UIImage.self) {
            itemProvider.loadObject(ofClass: UIImage.self) { (image, error) in
                DispatchQueue.main.async {
                    self.roomImageView.image = image as? UIImage
                    self.removeImageButtonSetup()
                }
            }
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }
    
    private func removeImageButtonSetup() {
        let removeImageButton: UIButton = {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: "minus.circle.fill"), for: .normal)
            button.addTarget(self, action: #selector(removeImageButtonTapped(_:)), for: .touchUpInside)
            button.tintColor = .red
            
            return button
        }()
        
        view.addSubview(removeImageButton)
        
        removeImageButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            removeImageButton.centerXAnchor.constraint(equalTo: roomImageView.leadingAnchor),
            removeImageButton.centerYAnchor.constraint(equalTo: roomImageView.bottomAnchor),
            removeImageButton.widthAnchor.constraint(equalToConstant: 30),
            removeImageButton.heightAnchor.constraint(equalToConstant: 30)
        ])

        if let image = roomImageView.image {
            if image.isEqual(UIImage(systemName: "photo")) {
                removeImageButton.isHidden = true
            } else {
                removeImageButton.isHidden = false
            }
        }
    }
    
    @objc private func removeImageButtonTapped(_ sender: UIButton) {
        roomImageView.image = UIImage(systemName: "photo")
        
        sender.isHidden = true
    }
    
    private func setCreateButton(_ button: UIButton) {
        button.clipsToBounds = true
        button.layer.cornerRadius = 10
        button.backgroundColor = UIColor(white: 0.1, alpha: 0.03)
    }
    
    @IBAction func createBtnTapped(_ sender: UIButton) {
        
        createButton.isEnabled = false
        activityIndicator.startAnimating()
        
        
        Task {
            do {
                
                if try await FirebaseManager.shared.checkDuplicate(strToCompare: self.roomNameTextView.text, fieldToCompare: "roomName", collectionName: "Rooms") {
                    await MainActor.run {
                        self.activityIndicator.stopAnimating()
                        createButton.isEnabled = true
                        AlertManager.showAlert(title: "중복된 방 이름", message: "이미 존재하는 방 이름입니다. 다른 이름을 선택해 주세요.", viewController: self)
                    }
                    return
                }
                
                let room = ChatRoom(roomName: self.roomNameTextView.text, roomDescription: self.roomDescriptionTextView.text, participants: [LoginManager.shared.getUserEmail], creatorID: LoginManager.shared.getUserEmail, createdAt: Date(), roomImageName: nil)
                
                await MainActor.run {
                    self.activityIndicator.stopAnimating()
                    self.performSegue(withIdentifier: "ToChatRoom", sender: room)
                }
                
                self.saveRoomInfo(room: room)
                
            } catch {
                
                await MainActor.run {
                    self.activityIndicator.stopAnimating()
                    AlertManager.showAlert(title: "오류", message: "방 생성 중 오류가 발생했습니다.", viewController: self)
                }
                
            }
        }
        
        
//        DispatchQueue.main.async {
//            self.activityIndicator.stopAnimating()
//            self.createButton.isEnabled = true
//            
//            Task {
//                if try await FirebaseManager.shared.checkDuplicate(strToCompare: self.roomNameTextView.text, fieldToCompare: "roomName", collectionName: "Rooms") {
//                    self.activityIndicator.stopAnimating()
//                    AlertManager.showAlert(title: "중복된 방 이름", message: "이미 존재하는 방 이름입니다. 다른 이름을 선택해 주세요.", viewController: self)
//                    return
//                }
//        }
//        
//        
//        let room = ChatRoom(id: UUID().uuidString, roomName: self.roomNameTextView.text, roomDescription: self.roomDescriptionTextView.text, participants: [LoginManager.shared.getUserEmail], creatorID: LoginManager.shared.getUserEmail, createdAt: Date(), roomImageName: nil)
//        
//        // 채팅방 화면으로 이동
//        self.performSegue(withIdentifier: "ToChatRoom", sender: room)
//        
//        // 백그라운드에서 방 정보 저장
//        self.saveRoomInfo(room: room)
//    }
        
        
    }
    
    private func saveRoomInfo(room: ChatRoom) {
        
        if let image = roomImageView.image {
                uploadImageAndSaveRoomInfo(image: image, roomInfo: room)
        } else {
            saveRoomInfoToFirestore(room: room, image: nil)
        }
        
    }
    
    
    private func uploadImageAndSaveRoomInfo(image: UIImage, roomInfo: ChatRoom) {
        
        Task {
            do {
                
                let imageName = try await FirebaseStorageManager.shared.uploadImageToStorage(image: image, location: ImageLocation.RoomImage)
                
                var updatedRoomInfo = roomInfo
                updatedRoomInfo.roomImageName = imageName
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
                if let imageName = room.roomImageName, let image = image {
                    KingfisherManager.shared.cache.store(image, forKey: imageName)
                }
                
                Task {
                    try await FirebaseManager.shared.updateRoomParticipant(room: room, isAdding: true)
                }

                NotificationCenter.default.post(name: .roomSavedComplete, object: nil, userInfo: ["room": room])
                
            case .failure:
                NotificationCenter.default.post(name: .roomSaveFailed, object: nil, userInfo: ["error": RoomCreationError.saveFailed])
                
            }
        }
    }
    
    private func enableCreateBtn() {
        if !roomNameTextView.text.isEmpty && !roomDescriptionTextView.text.isEmpty {
            createButton.isEnabled = true
        } else {
            createButton.isEnabled = false
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "ToChatRoom",
           let chatRoomVC = segue.destination as? ChatViewController,
           let tempRoomInfo = sender as? ChatRoom {
            chatRoomVC.room = tempRoomInfo
            chatRoomVC.isRoomSaving = true
        }
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
        
        return updatedText.count <= 20
    }
    
    func textViewDidChange(_ textView: UITextView) {
        guard let text = textView.text else { return }
        
        switch textView {
        case roomNameTextView:
            roomNameCountLabel.text = "\(text.count) / 20"
        case roomDescriptionTextView:
            roomDescriptionCountLabel.text = "\(text.count) / 20"
        default:
            break
        }
        
        enableCreateBtn()
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

extension Notification.Name {
    static let roomSavedComplete = Notification.Name("roomSaveCompleted")
    static let roomSaveFailed = Notification.Name("roomSaveFailed")
}

enum RoomCreationError: Error {
    case duplicateName
    case saveFailed
    case imageUploadFailed
}