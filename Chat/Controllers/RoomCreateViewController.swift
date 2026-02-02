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
    
    let addImageButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "plus.circle.fill"), for: .normal)
        
        return button
    }()
    
    let removeImageButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "minus.circle.fill"), for: .normal)
        button.tintColor = .red
        
        return button
    }()
    
    private lazy var cancellables: Set<AnyCancellable> = []
    
    let maxHeight: CGFloat = 300
    
    private var isDefaultRoomImage = true
    private var imageData: MediaManager.ImagePair?

    override func viewDidLoad() {
        super.viewDidLoad()

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
    
    // MARK: 버튼 관련
    @objc func cancelButtonTapped() {
        let alert = UIAlertController(title: "채팅방 개설을 취소하시겠어요?", message: nil, preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "계속 작성하기", style: .default, handler: nil))
        alert.addAction(UIAlertAction(title: "개설 취소하기", style: .destructive, handler:  { _ in
            ChatModalTransitionManager.dismiss(from: self)
        }))
        
        self.present(alert, animated: true, completion: nil)
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
    
    private func enableCreateBtn() {
        if !roomNameTextView.text.isEmpty && !roomDescriptionTextView.text.isEmpty {
            createBtn.isEnabled = true
        } else {
            createBtn.isEnabled = false
        }
    }
    
    @MainActor
    @objc func handleCreateButtonTap() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            
            // UI lock & spinner 시작
            self.createBtn.isEnabled = false
            LoadingIndicator.shared.start(on: self)
            defer {
                // 어떤 경로로 빠져도 UI 복구
                LoadingIndicator.shared.stop()
                self.createBtn.isEnabled = true
            }
            
            // 1) 입력값 정리 및 검증
            let name = self.roomNameTextView.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let desc = self.roomDescriptionTextView.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !desc.isEmpty else {
                AlertManager.showAlertNoHandler(title: "정보 부족", message: "방 이름과 설명을 입력해주세요.", viewController: self)
                return
            }
            
            do {
                // 2) 중복 이름 검사
                let isDup = try await FirebaseManager.shared.checkDuplicate(
                    strToCompare: name,
                    fieldToCompare: "roomName",
                    collectionName: "Rooms"
                )
                if isDup {
                    AlertManager.showAlertNoHandler(title: "중복된 방 이름", message: "이미 존재하는 방 이름입니다. 다른 이름을 선택해 주세요.", viewController: self)
                    return
                }
                
                // 3) Room 모델 구성
                let ref = Firestore.firestore().collection("Rooms").document()
                let room = ChatRoom(
                    ID: ref.documentID,
                    roomName: name,
                    roomDescription: desc,
                    participants: [LoginManager.shared.getUserEmail],
                    creatorID: LoginManager.shared.getUserEmail,
                    createdAt: Date()
                )
                
                // 4) 화면 전환 (즉시)
                let storyboard = UIStoryboard(name: "Main", bundle: nil)
                guard let chatRoomVC = storyboard.instantiateViewController(withIdentifier: "chatRoomVC") as? ChatViewController,
                      let presenter = self.presentingViewController else {
                    return
                }
                chatRoomVC.room = room
                chatRoomVC.isRoomSaving = true
                chatRoomVC.modalPresentationStyle = .fullScreen
                
                self.dismiss(animated: false) {
                    presenter.present(chatRoomVC, animated: true)
                }

                // 4.5) Firestore에 방 저장 + Socket.IO join (백그라운드, 실패 허용)
                Task.detached { [weak self] in
                    guard let self = self else { return }
                    do {
                        try await FirebaseManager.shared.saveRoomInfoToFirestore(room: room)
                        await MainActor.run {
                            NotificationCenter.default.post(name: .roomSavedComplete, object: nil, userInfo: ["room": room])
                        }
                    } catch {
                        await MainActor.run {
                            NotificationCenter.default.post(name: .roomSaveFailed, object: nil, userInfo: ["error": error])
                        }
                    }
                }

                // 5) 대표 이미지 업로드 (선택적 / 실패 허용)
                if self.isDefaultRoomImage == false, let pair = self.imageData {
                    Task.detached(priority: .background) {
                        do {
                            let (thumbPath, _) = try await FirebaseStorageManager.shared.uploadAndSave(
                                sha: pair.fileBaseName,
                                uid: room.ID ?? "",
                                type: .RoomImage,
                                thumbData: pair.thumbData,
                                originalFileURL: pair.originalFileURL
                            )
                            
                            if let image = UIImage(data: pair.thumbData) {
                                KingFisherCacheManager.shared.storeImage(image, forKey: thumbPath)
                            }
                        } catch {
                            // 업로드 실패는 치명적이지 않음. 추후 재시도 큐에서 처리 가능
                            print("방 대표 사진 업로드 실패: \(error)")
                        }
                    }
                }
            } catch {
                AlertManager.showAlertNoHandler(title: "오류", message: "방 생성 중 오류가 발생했습니다.", viewController: self)
            }
        }
    }
    
    
    private func addImageButtonSetup() {
        view.addSubview(addImageButton)
        addImageButton.addTarget(self, action: #selector(addImageButtonTapped), for: .touchUpInside)
        
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
        self.imageData = nil
        isDefaultRoomImage = true
        sender.isHidden = true
    }
    
    private func setupTextView(_ textView: UITextView) {
        textView.delegate = self
        textView.clipsToBounds = true
        textView.layer.cornerRadius = 10
        textView.backgroundColor = UIColor(white: 0.1, alpha: 0.03)
        textView.font = UIFont.preferredFont(forTextStyle: .headline)
        textView.font = UIFont.systemFont(ofSize: 15)
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

    // MARK: 키보드 관련
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
        
        Task { @MainActor in
            let p = try await MediaManager.shared.preparePairs(results)
            let pair = p.first!
            self.imageData = pair
            
            self.roomImageView.image = UIImage(data: pair.thumbData)
            self.isDefaultRoomImage = false
            
            self.removeImageButtonSetup()
        }
    }
}

extension RoomCreateViewController: UIImagePickerControllerDelegate & UINavigationControllerDelegate {
//    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
//        if let selectedImage = info[.originalImage] as? UIImage,
//           let cgImage = MediaManager.compressImageWithImageIO(selectedImage) {
//            self.roomImageView.image = UIImage(cgImage: cgImage)
//            self.roomImageView.accessibilityIdentifier = "Custom_Image"
//            self.removeImageButtonSetup()
//            self.enableCreateBtn()
//        } else if let editedImage = info[.editedImage] as? UIImage,
//                  let cgImage = MediaManager.compressImageWithImageIO(editedImage) {
//            self.roomImageView.image = UIImage(cgImage: cgImage)
//            self.roomImageView.accessibilityIdentifier = "Custom_Image"
//            self.removeImageButtonSetup()
//            self.enableCreateBtn()
//        }
//
//        picker.dismiss(animated: true, completion: nil)
//    }
//
//    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
//        picker.dismiss(animated: true, completion: nil)
//    }

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
