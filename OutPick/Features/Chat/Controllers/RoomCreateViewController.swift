//
//  RoomCreateViewController.swift
//  OutPick
//
//  Created by 김가윤 on 8/5/24.
//

import UIKit
import PhotosUI
import Combine

@MainActor
final class RoomCreateViewController: UIViewController, ChatModalAnimatable, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    private let rootContentView = RoomCreateContentView()
    
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
    private var viewModelCancellables: Set<AnyCancellable> = []
    
    let maxHeight: CGFloat = 300
    
    private var isDefaultRoomImage = true
    private var imageData: DefaultMediaProcessingService.ImagePair?
    private let roomCreateViewModel: RoomCreateViewModel
    private let makeCreatedRoomViewController: (ChatRoom) -> ChatViewController?

    private weak var createdChatRoomViewController: ChatViewController?

    private var roomNameTextView: UITextView { rootContentView.roomNameTextView }
    private var roomNameCountLabel: UILabel { rootContentView.roomNameCountLabel }
    private var roomDescriptionTextView: UITextView { rootContentView.roomDescriptionTextView }
    private var roomDescriptionCountLabel: UILabel { rootContentView.roomDescriptionCountLabel }
    private var scrollView: UIScrollView { rootContentView.scrollView }
    private var scrollViewTopConstraint: NSLayoutConstraint { rootContentView.scrollViewTopConstraint }
    private var roomImageView: UIImageView { rootContentView.roomImageView }
    private var activityIndicator: UIActivityIndicatorView { rootContentView.activityIndicator }

    init(
        viewModel: RoomCreateViewModel,
        makeCreatedRoomViewController: @escaping (ChatRoom) -> ChatViewController?
    ) {
        self.roomCreateViewModel = viewModel
        self.makeCreatedRoomViewController = makeCreatedRoomViewController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable, message: "Use init(...) for programmatic construction")
    required init?(coder: NSCoder) {
        fatalError("Storyboard initialization is no longer supported for RoomCreateViewController.")
    }

    override func loadView() {
        view = rootContentView
    }

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
        bindViewModel()
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
        guard createBtn.superview == nil else { return }
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
        roomCreateViewModel.submit()
    }
    
    
    private func addImageButtonSetup() {
        guard addImageButton.superview == nil else { return }
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
        if removeImageButton.superview == nil {
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
        
        removeImageButton.isHidden = isDefaultRoomImage
    }
    
    @objc private func removeImageButtonTapped(_ sender: UIButton) {
        cleanupTempImageIfNeeded(imageData)
        roomImageView.image = UIImage(named: "Default_Profile")
        self.imageData = nil
        isDefaultRoomImage = true
        roomCreateViewModel.updateSelectedImagePair(nil)
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

        return false
    }
    
    func textViewDidChange(_ textView: UITextView) {
        guard let text = textView.text else { return }
        
        switch textView {
        case roomNameTextView:
            roomCreateViewModel.updateRoomName(text)
        case roomDescriptionTextView:
            roomCreateViewModel.updateRoomDescription(text)
        default:
            break
        }
    }
}

extension RoomCreateViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true, completion: nil)
        
        Task { @MainActor in
            guard !results.isEmpty else { return }
            let p = try await DefaultMediaProcessingService.shared.preparePairs(results)
            guard let pair = p.first else { return }
            self.cleanupTempImageIfNeeded(self.imageData)
            self.imageData = pair
            self.roomCreateViewModel.updateSelectedImagePair(pair)
            
            self.roomImageView.image = UIImage(data: pair.thumbData)
            self.isDefaultRoomImage = false
            
            self.removeImageButtonSetup()
        }
    }
}

private extension RoomCreateViewController {
    func cleanupTempImageIfNeeded(_ pair: DefaultMediaProcessingService.ImagePair?) {
        guard let pair else { return }
        try? FileManager.default.removeItem(at: pair.originalFileURL)
    }

    func bindViewModel() {
        viewModelCancellables.removeAll()

        roomCreateViewModel.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.renderViewModelState(state)
            }
            .store(in: &viewModelCancellables)

        roomCreateViewModel.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleViewModelEvent(event)
            }
            .store(in: &viewModelCancellables)

        roomCreateViewModel.updateRoomName(roomNameTextView.text ?? "")
        roomCreateViewModel.updateRoomDescription(roomDescriptionTextView.text ?? "")
        roomCreateViewModel.updateSelectedImagePair(imageData)
    }

    func renderViewModelState(_ state: RoomCreateViewModel.State) {
        createBtn.isEnabled = state.isCreateEnabled
        roomNameCountLabel.text = "\(state.roomNameCount) / 20"
        roomDescriptionCountLabel.text = "\(state.roomDescriptionCount) / 200"
        roomNameTextView.isEditable = !state.isSubmitting
        roomDescriptionTextView.isEditable = !state.isSubmitting
        addImageButton.isEnabled = !state.isSubmitting
        removeImageButton.isEnabled = !state.isSubmitting

        if state.isSubmitting {
            LoadingIndicator.shared.start(on: self)
        } else {
            LoadingIndicator.shared.stop()
        }
    }

    func handleViewModelEvent(_ event: RoomCreateViewModel.Event) {
        switch event {
        case .showAlert(let title, let message):
            AlertManager.showAlertNoHandler(title: title, message: message, viewController: self)

        case .presentCreatedRoom(let room):
            presentCreatedRoom(room)

        case .roomSaveCompleted(let room):
            createdChatRoomViewController?.handleRoomCreationSaveCompleted(savedRoom: room)
        }
    }

    func presentCreatedRoom(_ room: ChatRoom) {
        guard let presenter = self.presentingViewController else { return }
        guard let chatRoomVC = makeCreatedRoomViewController(room: room) else { return }

        createdChatRoomViewController = chatRoomVC

        self.dismiss(animated: false) { [weak presenter] in
            presenter?.present(chatRoomVC, animated: true)
        }
    }

    func makeCreatedRoomViewController(room: ChatRoom) -> ChatViewController? {
        guard let chatRoomVC = makeCreatedRoomViewController(room) else {
            assertionFailure("RoomCreateViewController requires coordinator-owned room routing.")
            return nil
        }
        chatRoomVC.isRoomSaving = true
        chatRoomVC.modalPresentationStyle = .fullScreen
        return chatRoomVC
    }

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
