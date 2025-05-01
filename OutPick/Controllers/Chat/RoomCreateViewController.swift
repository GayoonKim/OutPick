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

class RoomCreateViewController: UIViewController {
    
    @IBOutlet weak var roomNameTextView: UITextView!
    @IBOutlet weak var roomNameCountLabel: UILabel!
    @IBOutlet weak var roomDescriptionTextView: UITextView!
    @IBOutlet weak var roomDescriptionCountLabel: UILabel!
    @IBOutlet weak var createButton: UIButton!
    @IBOutlet weak var scrollView: UIScrollView!
    
    @IBOutlet weak var roomImageView: UIImageView!
    
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    
    var roomInfo: ChatRoom?
    private var isDefaultRoomImage = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupTextView(roomNameTextView)
        setupTextView(roomDescriptionTextView)
        addImageButtonSetup()
        setCreateButton(createButton)

        let cancelButton = UIBarButtonItem(image: UIImage(systemName: "xmark"), style: .plain, target: self, action: #selector(cancelButtonTapped))
        cancelButton.tintColor = .black
        self.navigationItem.leftBarButtonItem = cancelButton
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
        
        // 초기 이미지가 기본 이미지인지 확인
        if let currentImage = roomImageView.image,
           let defaultImage = UIImage(named: "Default_Profile"),
           currentImage.pngData() == defaultImage.pngData() {
            isDefaultRoomImage = true
        }

        self.roomImageView.clipsToBounds = true
        self.roomImageView.layer.cornerRadius = 15
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    @objc func cancelButtonTapped() {
        let alert = UIAlertController(title: "채팅방 개설을 취소하시겠어요?", message: nil, preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "취소", style: .default, handler: nil))
        alert.addAction(UIAlertAction(title: "나가기", style: .destructive, handler:  { _ in
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
        textView.font = UIFont.systemFont(ofSize: 12)
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

        if let current_image_data = roomImageView.image?.pngData(),
           let new_image_data = UIImage(named: "Default_Profile")?.pngData(),
           current_image_data == new_image_data {
            removeImageButton.isHidden = true
        } else {
            removeImageButton.isHidden = false
        }
    }
    
    @objc private func removeImageButtonTapped(_ sender: UIButton) {
        roomImageView.image = UIImage(named: "Default_Profile")
        isDefaultRoomImage = true
        sender.isHidden = true
    }
    
    private func setCreateButton(_ button: UIButton) {
        button.clipsToBounds = true
        button.layer.cornerRadius = 10
        button.backgroundColor = UIColor(white: 0.1, alpha: 0.03)
    }
    
    @IBAction func createBtnTapped(_ sender: UIButton) {
        
        DispatchQueue.main.async {
            self.createButton.isEnabled = false
            LoadingIndicator.shared.start(on: self)
        }
        
        Task {
            do {
                
                if try await FirebaseManager.shared.checkDuplicate(strToCompare: self.roomNameTextView.text, fieldToCompare: "roomName", collectionName: "Rooms") {
                    await MainActor.run {
                        LoadingIndicator.shared.stop()
                        createButton.isEnabled = true
                        AlertManager.showAlertNoHandler(title: "중복된 방 이름", message: "이미 존재하는 방 이름입니다. 다른 이름을 선택해 주세요.", viewController: self)
                    }
                    return
                }
                
                let room = ChatRoom(ID: nil, roomName: self.roomNameTextView.text, roomDescription: self.roomDescriptionTextView.text, participants: [LoginManager.shared.getUserEmail], creatorID: LoginManager.shared.getUserEmail, createdAt: Date(), roomImageName: nil)
                
                self.performSegue(withIdentifier: "ToChatRoom", sender: room)

                self.saveRoomInfo(room: room)
                
            } catch {
                
                await MainActor.run {
                    LoadingIndicator.shared.stop()
                    AlertManager.showAlertNoHandler(title: "오류", message: "방 생성 중 오류가 발생했습니다.", viewController: self)
                }
                
            }
        }
        
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
            print("saveRoomInfoToFirestore completion 시작")

            switch result {
                
            case .success:
                if let imageName = room.roomImageName, let image = image {
                    KingfisherManager.shared.cache.store(image, forKey: imageName)
                }
                
                print("saveRoomInfoToFirestore completion 끝")
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
        
        if !roomNameTextView.text.isEmpty && !roomDescriptionTextView.text.isEmpty {
            enableCreateBtn()
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

extension Notification.Name {
    static let roomSavedComplete = Notification.Name("roomSaveCompleted")
    static let roomSaveFailed = Notification.Name("roomSaveFailed")
}

extension RoomCreateViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true, completion: nil)
        
        Task {
            let images = try await MediaManager.shared.dealWithImages(results)
            
            DispatchQueue.main.async {
                if let image = images.first {
                    self.roomImageView.image = image
                } else {
                    self.roomImageView.image = UIImage(named: "Default_Profile.png")
                }
                
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
            self.removeImageButtonSetup()
            self.enableCreateBtn()
        } else if let editedImage = info[.editedImage] as? UIImage,
                  let cgImage = MediaManager.compressImageWithImageIO(editedImage) {
            self.roomImageView.image = UIImage(cgImage: cgImage)
            self.removeImageButtonSetup()
            self.enableCreateBtn()
        }
        
        picker.dismiss(animated: true, completion: nil)
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }
    
}
