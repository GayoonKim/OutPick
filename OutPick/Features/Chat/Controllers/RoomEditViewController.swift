//
//  RoomEditViewController.swift
//  OutPick
//
//  Created by 김가윤 on 6/14/25.
//

import UIKit
import Combine
import PhotosUI

@MainActor
final class RoomEditViewController: UIViewController, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UITextFieldDelegate, UITextViewDelegate {
    private let customNavigationBar: CustomNavigationBarView = {
        let navBar = CustomNavigationBarView()
        navBar.translatesAutoresizingMaskIntoConstraints = false
        return navBar
    }()

    private lazy var completeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("완료", for: .normal)
        button.setTitleColor(.black, for: .normal)
        button.setTitleColor(.placeholderText, for: .disabled)
        button.addTarget(self, action: #selector(completeButtonTapped), for: .touchUpInside)
        return button
    }()

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.alwaysBounceVertical = true
        sv.keyboardDismissMode = .interactive
        return sv
    }()

    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let headerImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(named: "Default_Profile")
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.backgroundColor = .secondarySystemBackground
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 12
        return imageView
    }()

    private let imageEditIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .center
        imageView.tintColor = .black
        imageView.backgroundColor = .white
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 13
        imageView.image = UIImage(systemName: "camera.fill")
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let nameField: UITextField = {
        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholder = "채팅방 이름 (필수)"
        textField.clearButtonMode = .never
        textField.borderStyle = .roundedRect
        textField.returnKeyType = .done
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        return textField
    }()

    private lazy var nameClearButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        button.tintColor = .tertiaryLabel
        button.addTarget(self, action: #selector(clearNameTapped), for: .touchUpInside)
        button.frame = CGRect(x: 0, y: 0, width: 28, height: 28)
        return button
    }()

    private let nameCountLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.text = "0/20"
        return label
    }()

    private let nameTitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabel
        label.text = "방 이름"
        return label
    }()

    private let descTitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabel
        label.text = "방 설명"
        return label
    }()

    private let descTextView: UITextView = {
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = .systemFont(ofSize: 15)
        textView.layer.cornerRadius = 8
        textView.layer.borderWidth = 1
        textView.layer.borderColor = UIColor.separator.cgColor
        textView.isScrollEnabled = false
        return textView
    }()

    private let descCountLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.text = "0/200"
        return label
    }()

    var onRoomEdited: (@MainActor (ChatRoom) async -> Void)?

    private let viewModel: RoomEditViewModel
    private var cancellables = Set<AnyCancellable>()
    private var convertImageTask: Task<Void, Never>?
    private var descHeightConstraint: NSLayoutConstraint?
    private var imageActionSheet: BottomActionSheetView?
    private let descMaxHeight: CGFloat = 220

    init(viewModel: RoomEditViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        convertImageTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        setupCustomNavigationBar()
        bindKeyboardPublisher()
        setupScrollUI()
        configureInputs()
        bindViewModel()
        viewModel.loadHeaderImageIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        adjustDescTextViewHeight()
        imageEditIconView.layer.cornerRadius = imageEditIconView.bounds.height / 2
    }

    private func configureInputs() {
        nameField.delegate = self
        descTextView.delegate = self
        nameField.rightView = nameClearButton
        nameField.rightViewMode = .whileEditing
        nameField.addTarget(self, action: #selector(nameFieldEditingChanged), for: .editingChanged)
    }

    private func bindViewModel() {
        viewModel.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.render(state)
            }
            .store(in: &cancellables)

        viewModel.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handle(event)
            }
            .store(in: &cancellables)
    }

    private func render(_ state: RoomEditViewModel.State) {
        if nameField.text != state.roomName {
            nameField.text = state.roomName
        }

        if descTextView.text != state.roomDescription {
            descTextView.text = state.roomDescription
            adjustDescTextViewHeight()
        }

        nameCountLabel.text = "\(state.roomNameCount)/20"
        descCountLabel.text = "\(state.roomDescriptionCount)/200"
        completeButton.isEnabled = state.isSubmitEnabled
        headerImageView.isUserInteractionEnabled = !state.isSubmitting
        nameField.isEnabled = !state.isSubmitting
        descTextView.isEditable = !state.isSubmitting
        nameClearButton.isEnabled = !state.isSubmitting

        if state.isSubmitting {
            LoadingIndicator.shared.start(on: self)
        } else {
            LoadingIndicator.shared.stop()
        }
    }

    private func handle(_ event: RoomEditViewModel.Event) {
        switch event {
        case .headerImageUpdated(let image):
            headerImageView.image = image

        case .showAlert(let title, let message):
            AlertManager.showAlertNoHandler(title: title, message: message, viewController: self)

        case .didComplete(let updatedRoom):
            Task { [weak self] in
                guard let self else { return }
                if let onRoomEdited = self.onRoomEdited {
                    await onRoomEdited(updatedRoom)
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                self.dismiss(animated: true)
            }
        }
    }

    private func bindKeyboardPublisher() {
        NotificationCenter.default.publisher(for: UIApplication.keyboardWillShowNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                self?.keyboardWillShow(notification)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.keyboardWillHideNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                self?.keyboardWillHide(notification)
            }
            .store(in: &cancellables)
    }

    private func keyboardWillShow(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }

        updateKeyboardInsets(showing: true, height: keyboardFrame.height)

        if descTextView.isFirstResponder {
            scrollDescIntoView(animated: true)
        }
    }

    private func keyboardWillHide(_ notification: Notification) {
        updateKeyboardInsets(showing: false, height: 0)
    }

    private func presentImgEditActionSheet() {
        imageActionSheet?.dismiss(animated: false)
        view.endEditing(true)

        var actions: [BottomActionSheetView.Action] = [
            .init(title: "사진 선택", handler: { [weak self] in
                self?.openPHPicker()
            }),
            .init(title: "사진 촬영", handler: { [weak self] in
                self?.openCamera()
            })
        ]

        if viewModel.shouldShowDeleteAction {
            actions.append(.init(title: "삭제", style: .destructive, handler: { [weak self] in
                self?.removeImage()
            }))
        }

        actions.append(.init(title: "취소", style: .cancel))

        let sheet = BottomActionSheetView.present(in: view, actions: actions)
        sheet.onDismiss = { [weak self] in
            self?.imageActionSheet = nil
        }
        imageActionSheet = sheet
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
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            AlertManager.showAlertNoHandler(
                title: "카메라 사용 불가",
                message: "현재 기기에서 카메라를 사용할 수 없습니다.",
                viewController: self
            )
            return
        }

        let imagePicker = UIImagePickerController()
        imagePicker.delegate = self
        imagePicker.allowsEditing = true
        imagePicker.sourceType = .camera

        present(imagePicker, animated: true)
    }

    private func removeImage() {
        headerImageView.image = UIImage(named: "Default_Profile")
        viewModel.removeImage()
    }

    private func convertPickerResults(_ results: [PHPickerResult]) {
        convertImageTask?.cancel()
        convertImageTask = Task { [weak self] in
            guard let self else { return }
            do {
                let pairs = try await DefaultMediaProcessingService.shared.preparePairs(results)
                guard !Task.isCancelled, let pair = pairs.first else { return }
                self.viewModel.selectImage(pair)
            } catch {
                AlertManager.showAlertNoHandler(
                    title: "이미지 변환 실패",
                    message: "이미지를 다시 선택해 주세요.",
                    viewController: self
                )
            }
        }
    }

    private func convertCameraImage(_ image: UIImage) {
        convertImageTask?.cancel()
        do {
            let pair = try makeImagePair(from: image)
            viewModel.selectImage(pair)
        } catch {
            AlertManager.showAlertNoHandler(
                title: "이미지 변환 실패",
                message: "촬영한 이미지를 다시 확인해 주세요.",
                viewController: self
            )
        }
    }

    private func makeImagePair(from image: UIImage) throws -> DefaultMediaProcessingService.ImagePair {
        guard let originalData = image.jpegData(compressionQuality: 0.95) else {
            throw MediaError.failedToConvertImage
        }

        guard let thumbData = DefaultMediaProcessingService.makeThumbnailData(from: image) else {
            throw MediaError.failedToCreateImageData
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("picked-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        try originalData.write(to: fileURL, options: .atomic)

        let width = image.cgImage?.width ?? Int(image.size.width * image.scale)
        let height = image.cgImage?.height ?? Int(image.size.height * image.scale)
        let fileBaseName = UUID().uuidString.replacingOccurrences(of: "-", with: "")

        return DefaultMediaProcessingService.ImagePair(
            index: 0,
            originalFileURL: fileURL,
            thumbData: thumbData,
            originalWidth: width,
            originalHeight: height,
            bytesOriginal: originalData.count,
            sha256: fileBaseName
        )
    }
}

extension RoomEditViewController {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty else { return }
        convertPickerResults(results)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let pickedImage = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
        picker.dismiss(animated: true)

        guard let pickedImage else { return }
        convertCameraImage(pickedImage)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

extension RoomEditViewController {
    private func setupCustomNavigationBar() {
        view.addSubview(customNavigationBar)

        NSLayoutConstraint.activate([
            customNavigationBar.topAnchor.constraint(equalTo: view.topAnchor),
            customNavigationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            customNavigationBar.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        customNavigationBar.configure(
            leftViews: [UIButton.navBackButton(action: backButtonTapped)],
            centerViews: [UILabel.navTitle("오픈채팅 관리")],
            rightViews: [completeButton]
        )
    }

    private func backButtonTapped() {
        dismiss(animated: true)
    }

    @objc
    private func completeButtonTapped() {
        view.endEditing(true)
        viewModel.submit()
    }

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

        let initialDescHeightConstraint = descTextView.heightAnchor.constraint(equalToConstant: 120)
        descHeightConstraint = initialDescHeightConstraint

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

    @objc
    private func imageEditTapped() {
        presentImgEditActionSheet()
    }

    @objc
    private func clearNameTapped() {
        nameField.text = ""
        viewModel.clearRoomName()
    }

    @objc
    private func nameFieldEditingChanged() {
        viewModel.updateRoomName(nameField.text ?? "")
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let current = textField.text ?? ""
        guard let textRange = Range(range, in: current) else { return true }
        let next = current.replacingCharacters(in: textRange, with: string)
        return next.count <= 20
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let current = textView.text ?? ""
        guard let textRange = Range(range, in: current) else { return true }
        let next = current.replacingCharacters(in: textRange, with: text)
        return next.count <= 200
    }

    func textViewDidChange(_ textView: UITextView) {
        viewModel.updateRoomDescription(textView.text ?? "")
        adjustDescTextViewHeight()
        if descTextView.isFirstResponder {
            scrollDescIntoView(animated: false)
        }
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        guard textView === descTextView else { return }
        adjustDescTextViewHeight()
        scrollDescIntoView(animated: true)
    }

    private func adjustDescTextViewHeight() {
        let width = descTextView.bounds.width
        guard width > 0 else { return }

        let fittingSize = descTextView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let minHeight: CGFloat = 120
        let targetHeight = min(max(fittingSize.height, minHeight), descMaxHeight)
        descHeightConstraint?.constant = targetHeight

        let shouldScroll = fittingSize.height > descMaxHeight
        if descTextView.isScrollEnabled != shouldScroll {
            descTextView.isScrollEnabled = shouldScroll
            if !shouldScroll {
                descTextView.setContentOffset(.zero, animated: false)
            }
        }
    }

    private func updateKeyboardInsets(showing: Bool, height: CGFloat) {
        let bottomInset = showing ? (height + 16) : 0
        scrollView.contentInset.bottom = bottomInset
        scrollView.verticalScrollIndicatorInsets.bottom = bottomInset
    }

    private func scrollDescIntoView(animated: Bool) {
        let rectInScroll = descTextView.convert(descTextView.bounds, to: scrollView)
        scrollView.scrollRectToVisible(rectInScroll.insetBy(dx: 0, dy: -16), animated: animated)
    }
}
