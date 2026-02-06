//
//  ChatEditViewController.swift
//  OutPick
//
//  Created by 김가윤 on 6/14/25.
//

import UIKit
import Combine
import PhotosUI
import FirebaseStorage

class RoomEditViewController: UIViewController, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UITextFieldDelegate, UITextViewDelegate {
    let customNavigationBar: CustomNavigationBarView = {
        let navBar = CustomNavigationBarView()
        navBar.translatesAutoresizingMaskIntoConstraints = false
        
        return navBar
    }()

    // MARK: - Scroll & Content
    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.alwaysBounceVertical = true
        sv.keyboardDismissMode = .interactive
        return sv
    }()
    private let contentView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    // MARK: - Header Image
    private let headerImageView: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage(named: "Default_Profile")
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.backgroundColor = .secondarySystemBackground
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 12
        return iv
    }()
    private let imageEditIconView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .center
        iv.tintColor = .black
        iv.backgroundColor = .white
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 13
        iv.image = UIImage(systemName: "camera.fill")
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    // MARK: - Name Field
    private let nameField: UITextField = {
        let tf = UITextField()
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.placeholder = "채팅방 이름 (필수)"
        tf.clearButtonMode = .never // 별도 버튼 제공
        tf.borderStyle = .roundedRect
        tf.returnKeyType = .done
        tf.autocorrectionType = .no
        tf.autocapitalizationType = .none
        return tf
    }()
    private lazy var nameClearButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        b.tintColor = .tertiaryLabel
        b.addTarget(self, action: #selector(clearNameTapped), for: .touchUpInside)
        b.frame = CGRect(x: 0, y: 0, width: 28, height: 28)
        return b
    }()
    private let nameCountLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 12)
        l.textColor = .secondaryLabel
        l.text = "0/20"
        return l
    }()

    // MARK: - Field Titles
    private let nameTitleLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 13, weight: .semibold)
        l.textColor = .secondaryLabel
        l.text = "방 이름"
        return l
    }()
    private let descTitleLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 13, weight: .semibold)
        l.textColor = .secondaryLabel
        l.text = "방 설명"
        return l
    }()

    // MARK: - Description Field
    private let descTextView: UITextView = {
        let tv = UITextView()
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.font = .systemFont(ofSize: 15)
        tv.layer.cornerRadius = 8
        tv.layer.borderWidth = 1
        tv.layer.borderColor = UIColor.separator.cgColor
        tv.isScrollEnabled = false
        return tv
    }()
    private let descCountLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 12)
        l.textColor = .secondaryLabel
        l.text = "0/200"
        return l
    }()

    var room: ChatRoom
    
    private var cancellables = Set<AnyCancellable>()
    
    private var currentKeyboardHeight: CGFloat?
    
    private var selectedImage: UIImage?
    private var selectedImageData: DefaultMediaProcessingService.ImagePair?
    private var isImageRemoved: Bool = false
    private var afterRoomname: String = ""
    private var afterDescription: String = ""
    private var convertImageTask: Task<Void, Error>? = nil
    private var headerImageTask: Task<Void, Never>? = nil
    private let descMaxHeight: CGFloat = 220
    private var descHeightConstraint: NSLayoutConstraint?
    private var isSubmitting: Bool = false
    
    var onCompleteEdit: ((UIImage?, DefaultMediaProcessingService.ImagePair?, Bool, String, String) async throws -> Void)?
    
    init(room: ChatRoom) {
        self.room = room
        self.afterRoomname = self.room.roomName
        self.afterDescription = self.room.roomDescription
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .white
        
        setupCustomNavigationBar()
        updateCompleteBtnState()
        bindKeyboardPublisher()
        setupScrollUI()
        // Seed initial values
        nameField.text = afterRoomname
        descTextView.text = afterDescription
        updateNameCount()
        updateDescCount()
        nameField.delegate = self
        descTextView.delegate = self
        // Right view clear button
        nameField.rightView = nameClearButton
        nameField.rightViewMode = .whileEditing
        loadHeaderImageIfAvailable()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cancellables.removeAll()
        convertImageTask?.cancel()
        headerImageTask?.cancel()
    }

    private func bindKeyboardPublisher() {
        NotificationCenter.default.publisher(for: UIApplication.keyboardWillShowNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self = self else { return }
                self.keyboardWillShow(notification)
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.keyboardWillHideNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self = self else { return }
                self.keyboardWillHide(notification)
            }
            .store(in: &cancellables)
    }
    
    private func keyboardWillShow(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let keyboardHeight = keyboardFrame.height
        self.currentKeyboardHeight = keyboardHeight
        updateKeyboardInsets(showing: true, height: keyboardHeight)
        if descTextView.isFirstResponder {
            scrollDescIntoView(animated: true)
        }
    }
    
    private func keyboardWillHide(_ notification: Notification) {
        self.currentKeyboardHeight = nil
        updateKeyboardInsets(showing: false, height: 0)
    }
    
    // MARK: - Header Image Loading
    private func loadHeaderImageIfAvailable() {
        let key = room.thumbPath ?? room.originalPath
        guard let path = key, !path.isEmpty else { return }
        headerImageTask = Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            do {
                let image = try await KingFisherCacheManager.shared.loadOrFetchImage(forKey: path, fetch: {
                    try await FirebaseStorageManager.shared.fetchImageFromStorage(image: path, location: .roomImage)
                })
                await MainActor.run {
                    self.headerImageView.image = image
                }
            } catch {
                // Optional: log or ignore
                print("[RoomEdit] header image load failed: \(error)")
            }
        }
    }

    private func presentImgEditActionSheet() {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "사진 선택", style: .default, handler: { _ in
            self.openPHPicker()
        }))

        alert.addAction(UIAlertAction(title: "사진 촬영", style: .default, handler: { _ in
            self.openCamera()
        }))

        // Show delete only when there is a custom image (picked or remote) and not already marked removed
        let hasRemote = (((self.room.thumbPath?.isEmpty == false) || (self.room.originalPath?.isEmpty == false)) && !self.isImageRemoved)
        let hasPicked = (self.selectedImage != nil) || (self.selectedImageData != nil)
        let hasCustom = hasRemote || hasPicked
        if hasCustom {
            alert.addAction(UIAlertAction(title: "삭제", style: .destructive, handler: { _ in
                self.removeImage()
            }))
        }

        alert.addAction(UIAlertAction(title: "취소", style: .cancel, handler: nil))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = self.view
            popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        self.present(alert, animated: true)
    }
    
    private func openPHPicker() {
        var configuration = PHPickerConfiguration()
        configuration.filter = .any(of: [.images])
        configuration.selectionLimit = 1
        configuration.selection = .ordered
        configuration.preferredAssetRepresentationMode = .current
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
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
    
    @MainActor
    private func removeImage() {
        // Cancel any ongoing header image load
        headerImageTask?.cancel()
        convertImageTask?.cancel()

        // Determine if there is an existing custom image (from room or a newly picked one)
        let hadRemoteImage = (room.thumbPath != nil) || (room.originalPath != nil)
        let hadPickedImage = (selectedImage != nil) || (selectedImageData != nil)
        let hasCustomImage = hadRemoteImage || hadPickedImage

        // If it's already the default and nothing to remove, just return
        if !hasCustomImage {
            self.headerImageView.image = UIImage(named: "Default_Profile")
            self.isImageRemoved = false
            updateCompleteBtnState()
            return
        }

        // UI: set default image immediately
        self.headerImageView.image = UIImage(named: "Default_Profile")

        // State: clear picked image and mark removal
        self.selectedImage = nil
        self.selectedImageData = nil
        self.isImageRemoved = true

        // Update complete button state
        updateCompleteBtnState()
    }
}

extension RoomEditViewController {
    @MainActor
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        for result in results {
            let itemProvider = result.itemProvider

            if itemProvider.canLoadObject(ofClass: UIImage.self) {
                convertImageTask = Task {
                    do {
                        let pairs = try await DefaultMediaProcessingService.shared.preparePairs(results)
                        if Task.isCancelled { return }
                        guard let pair = pairs.first else { return }
                        await MainActor.run {
                            self.selectedImageData = pair
                            if let img = UIImage(data: pair.thumbData) {
                                self.headerImageView.image = img
                                self.selectedImage = img
                                self.isImageRemoved = false
                                self.updateCompleteBtnState()
                            }
                        }
                    } catch {
                        await MainActor.run {
                            AlertManager.showAlertNoHandler(title: "이미지 변환 실패", message: "이미지를 다시 선택해 주세요/", viewController: self)
                        }
                    }
                }
            }
        }

    }
    
//    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
//        if let editedImage = info[.editedImage] as? UIImage {
//
//        } else if let originalImage = info[.originalImage] as? UIImage {
//
//        }
//
//        dismiss(animated: true)
//    }
//
//    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
//        picker.dismiss(animated: true)
//    }
}

extension RoomEditViewController {
    @MainActor
    func setupCustomNavigationBar() {
        self.view.addSubview(customNavigationBar)
        
        NSLayoutConstraint.activate([
            customNavigationBar.topAnchor.constraint(equalTo: self.view.topAnchor),
            customNavigationBar.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            customNavigationBar.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
        ])
        
        let completeBtn = UIButton(type: .system)
        completeBtn.setTitle("완료", for: .normal)
        completeBtn.setTitleColor(.black, for: .normal)
        completeBtn.setTitleColor(.placeholderText, for: .disabled)
        completeBtn.addTarget(self, action: #selector(completeBtnTapped), for: .touchUpInside)
        
        customNavigationBar.configure(leftViews: [UIButton.navBackButton(action: backBtnTapped)],
                                      centerViews: [UILabel.navTitle("오픈채팅 관리")],
                                      rightViews: [completeBtn])
    }
    
    private func backBtnTapped() {
        self.dismiss(animated: true)
    }
    
    @objc private func completeBtnTapped() {
        // Prevent double-taps
        if isSubmitting { return }
        view.endEditing(true)

        // Sanitize inputs
        let name = afterRoomname.trimmingCharacters(in: .whitespacesAndNewlines)
        let desc = afterDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        // Ensure handler exists
        guard let onCompleteEdit = self.onCompleteEdit else {
            AlertManager.showAlertNoHandler(title: "오류", message: "편집 완료 핸들러가 설정되지 않았습니다.", viewController: self)
            return
        }

        // Lock UI
        isSubmitting = true
        if let button = customNavigationBar.rightStack.arrangedSubviews
            .compactMap({ $0 as? UIButton })
            .first(where: { $0.currentTitle == "완료" }) {
            button.isEnabled = false
        }
        LoadingIndicator.shared.start(on: self)

        Task { [weak self] in
            guard let self = self else { return }
            do {
                try await onCompleteEdit(self.selectedImage, self.selectedImageData, self.isImageRemoved, name, desc)
                await MainActor.run {
                    LoadingIndicator.shared.stop()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    self.dismiss(animated: true)
                }
            } catch {
                await MainActor.run {
                    LoadingIndicator.shared.stop()
                    self.isSubmitting = false
                    self.updateCompleteBtnState() // re-enable if needed
                    AlertManager.showAlertNoHandler(title: "방 수정 실패", message: error.localizedDescription, viewController: self)
                }
            }
        }
    }
    
    private func updateCompleteBtnState() {
        if let button = customNavigationBar.rightStack.arrangedSubviews
            .compactMap({ $0 as? UIButton })
            .first(where: { $0.currentTitle == "완료" }) {
            let isNameValid = self.afterRoomname != "채팅방 이름 (필수)" && self.afterRoomname != self.room.roomName
            let isDescriptionValid = self.afterDescription != self.room.roomDescription
            let imageChanged = (self.selectedImage != nil) || (self.isImageRemoved && ((self.room.thumbPath != nil) || (self.room.originalPath != nil)))
            button.isEnabled = isNameValid || isDescriptionValid || imageChanged
        }
    }

    // MARK: - UI Layout
    @MainActor
    private func setupScrollUI() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: customNavigationBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        // Prepare dynamic height constraint for description
        let initialDescHeightConstraint = descTextView.heightAnchor.constraint(equalToConstant: 120)
        self.descHeightConstraint = initialDescHeightConstraint

        // Tap gesture on the whole header image view
        headerImageView.isUserInteractionEnabled = true
        let headerTap = UITapGestureRecognizer(target: self, action: #selector(imageEditTapped))
        headerImageView.addGestureRecognizer(headerTap)

        contentView.addSubview(headerImageView)
        contentView.addSubview(nameTitleLabel)
        contentView.addSubview(nameField)
        contentView.addSubview(nameCountLabel)
        contentView.addSubview(descTitleLabel)
        contentView.addSubview(descTextView)
        contentView.addSubview(descCountLabel)
        headerImageView.addSubview(imageEditIconView)

        let side: CGFloat = 220
        NSLayoutConstraint.activate([
            headerImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            headerImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            headerImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            headerImageView.heightAnchor.constraint(equalToConstant: side),

            imageEditIconView.trailingAnchor.constraint(equalTo: headerImageView.trailingAnchor, constant: -12),
            imageEditIconView.bottomAnchor.constraint(equalTo: headerImageView.bottomAnchor, constant: -12),
            imageEditIconView.widthAnchor.constraint(equalToConstant: 32),
            imageEditIconView.heightAnchor.constraint(equalToConstant: 32),

            nameTitleLabel.topAnchor.constraint(equalTo: headerImageView.bottomAnchor, constant: 20),
            nameTitleLabel.leadingAnchor.constraint(equalTo: headerImageView.leadingAnchor),
            nameTitleLabel.trailingAnchor.constraint(equalTo: headerImageView.trailingAnchor),

            nameField.topAnchor.constraint(equalTo: nameTitleLabel.bottomAnchor, constant: 6),
            nameField.leadingAnchor.constraint(equalTo: headerImageView.leadingAnchor),
            nameField.trailingAnchor.constraint(equalTo: headerImageView.trailingAnchor),
            nameField.heightAnchor.constraint(equalToConstant: 44),

            nameCountLabel.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 6),
            nameCountLabel.trailingAnchor.constraint(equalTo: nameField.trailingAnchor),

            descTitleLabel.topAnchor.constraint(equalTo: nameCountLabel.bottomAnchor, constant: 16),
            descTitleLabel.leadingAnchor.constraint(equalTo: nameField.leadingAnchor),
            descTitleLabel.trailingAnchor.constraint(equalTo: nameField.trailingAnchor),

            descTextView.topAnchor.constraint(equalTo: descTitleLabel.bottomAnchor, constant: 6),
            descTextView.leadingAnchor.constraint(equalTo: nameField.leadingAnchor),
            descTextView.trailingAnchor.constraint(equalTo: nameField.trailingAnchor),
            initialDescHeightConstraint,

            descCountLabel.topAnchor.constraint(equalTo: descTextView.bottomAnchor, constant: 6),
            descCountLabel.trailingAnchor.constraint(equalTo: descTextView.trailingAnchor),
            descCountLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24)
        ])
        
    }

    // MARK: - Actions
    @objc private func imageEditTapped() {
        presentImgEditActionSheet()
    }

    @objc private func clearNameTapped() {
        nameField.text = ""
        afterRoomname = ""
        updateNameCount()
        updateCompleteBtnState()
    }

    // MARK: - Counters & Limits
    private func updateNameCount() {
        let count = nameField.text?.count ?? 0
        nameCountLabel.text = "\(count)/20"
    }

    private func updateDescCount() {
        let count = descTextView.text?.count ?? 0
        descCountLabel.text = "\(count)/200"
    }
    

    // MARK: - UITextFieldDelegate / UITextViewDelegate
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        // Enforce 20 chars
        let current = textField.text ?? ""
        guard let r = Range(range, in: current) else { return true }
        let next = current.replacingCharacters(in: r, with: string)
        if next.count > 20 { return false }
        afterRoomname = next
        updateNameCount()
        // 버튼 상태 갱신
        DispatchQueue.main.async { [weak self] in self?.updateCompleteBtnState() }
        return true
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // Enforce 200 chars
        let current = textView.text ?? ""
        guard let r = Range(range, in: current) else { return true }
        let next = current.replacingCharacters(in: r, with: text)
        if next.count > 200 { return false }
        return true
    }

    func textViewDidChange(_ textView: UITextView) {
        afterDescription = textView.text ?? ""
        updateDescCount()
        updateCompleteBtnState()
        adjustDescTextViewHeight()
        if descTextView.isFirstResponder {
            scrollDescIntoView(animated: false)
        }
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        if textView === descTextView {
            adjustDescTextViewHeight()
            scrollDescIntoView(animated: true)
        }
    }

    // MARK: - Dynamic TextView Sizing
    private func adjustDescTextViewHeight() {
        let width = descTextView.bounds.width
        if width <= 0 { return }
        let fitting = descTextView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let minH: CGFloat = 120
        let target = min(max(fitting.height, minH), descMaxHeight)
        descHeightConstraint?.constant = target
        let shouldScroll = fitting.height > descMaxHeight
        if descTextView.isScrollEnabled != shouldScroll {
            descTextView.isScrollEnabled = shouldScroll
            if !shouldScroll { descTextView.setContentOffset(.zero, animated: false) }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        adjustDescTextViewHeight()
        imageEditIconView.layer.cornerRadius = imageEditIconView.bounds.height / 2
    }

    // MARK: - Keyboard Insets & Scrolling
    private func updateKeyboardInsets(showing: Bool, height: CGFloat) {
        let bottom = showing ? (height + 16) : 0
        scrollView.contentInset.bottom = bottom
        scrollView.verticalScrollIndicatorInsets.bottom = bottom
    }

    private func scrollDescIntoView(animated: Bool) {
        let rectInScroll = descTextView.convert(descTextView.bounds, to: scrollView)
        scrollView.scrollRectToVisible(rectInScroll.insetBy(dx: 0, dy: -16), animated: animated)
    }
}
