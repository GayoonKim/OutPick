import PhotosUI
import UIKit

final class ProfileEditViewController: UIViewController {
    private let viewModel: ProfileEditViewModel
    private let avatarImageManager: AvatarImageManaging
    private let mediaProcessor: MediaProcessingServiceProtocol
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let headerView = MyPageEditorialHeaderView()
    private let avatarContainer = UIView()
    private let imageView = UIImageView()
    private let nicknameField = UITextField()
    private let nicknameLabel = UILabel()
    private let nicknameRuleLabel = UILabel()
    private let chooseButton = UIButton(type: .system)
    private let removeButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let errorLabel = UILabel()
    private var remoteLoadTask: Task<Void, Never>?

    init(
        viewModel: ProfileEditViewModel,
        avatarImageManager: AvatarImageManaging,
        mediaProcessor: MediaProcessingServiceProtocol = DefaultMediaProcessingService()
    ) {
        self.viewModel = viewModel
        self.avatarImageManager = avatarImageManager
        self.mediaProcessor = mediaProcessor
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        bind()
        loadRemoteAvatar(path: viewModel.state.remoteAvatarPath)
    }

    private func configureUI() {
        view.backgroundColor = OutPickTheme.ColorToken.backgroundBase
        navigationItem.title = ""
        navigationController?.setNavigationBarHidden(false, animated: false)
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.delaysContentTouches = false
        headerView.configure(
            eyebrow: "PROFILE EDIT",
            title: "보여주고 싶은\n나의 모습",
            subtitle: "OutPick에서 사용할 이름과 이미지를 정리해요"
        )

        imageView.image = UIImage(named: "Default_Profile")
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 64
        imageView.layer.borderWidth = 1
        imageView.layer.borderColor = OutPickTheme.ColorToken.borderStrong.cgColor
        imageView.backgroundColor = OutPickTheme.ColorToken.surfaceBase
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = "선택한 프로필 이미지"

        nicknameLabel.text = "NICKNAME"
        nicknameLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        nicknameLabel.textColor = OutPickTheme.ColorToken.accent

        nicknameField.borderStyle = .none
        nicknameField.placeholder = "닉네임"
        nicknameField.font = MyPageEditorialStyle.serifFont(size: 25, weight: .semibold)
        nicknameField.textColor = OutPickTheme.ColorToken.textPrimary
        nicknameField.tintColor = OutPickTheme.ColorToken.accent
        nicknameField.backgroundColor = .clear
        nicknameField.autocorrectionType = .no
        nicknameField.clearButtonMode = .whileEditing
        nicknameField.addTarget(self, action: #selector(nicknameChanged), for: .editingChanged)

        nicknameRuleLabel.text = "2–20자 · 다른 사용자와 겹치지 않는 이름"
        nicknameRuleLabel.font = .preferredFont(forTextStyle: .caption1)
        nicknameRuleLabel.textColor = OutPickTheme.ColorToken.textTertiary

        var chooseConfiguration = UIButton.Configuration.plain()
        chooseConfiguration.title = "사진 선택"
        chooseConfiguration.image = UIImage(systemName: "camera")
        chooseConfiguration.imagePadding = 7
        chooseConfiguration.baseForegroundColor = OutPickTheme.ColorToken.textPrimary
        chooseButton.configuration = chooseConfiguration
        chooseButton.addTarget(self, action: #selector(chooseTapped), for: .touchUpInside)

        var removeConfiguration = UIButton.Configuration.plain()
        removeConfiguration.title = "이미지 제거"
        removeConfiguration.baseForegroundColor = OutPickTheme.ColorToken.destructive
        removeButton.configuration = removeConfiguration
        removeButton.addTarget(self, action: #selector(removeTapped), for: .touchUpInside)

        MyPageEditorialStyle.configurePrimaryButton(saveButton, title: "변경사항 저장")
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        activityIndicator.color = OutPickTheme.ColorToken.accent
        errorLabel.textColor = OutPickTheme.ColorToken.destructive
        errorLabel.font = .systemFont(ofSize: 13)
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0

        avatarContainer.addSubview(imageView)
        let photoActions = UIStackView(arrangedSubviews: [chooseButton, removeButton])
        photoActions.axis = .horizontal
        photoActions.distribution = .fillEqually
        photoActions.spacing = 12

        let underline = UIView()
        underline.backgroundColor = OutPickTheme.ColorToken.borderStrong

        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 0
        [
            headerView, avatarContainer, photoActions, nicknameLabel,
            nicknameField, underline, nicknameRuleLabel, errorLabel, activityIndicator
        ].forEach(contentStack.addArrangedSubview)
        contentStack.setCustomSpacing(34, after: headerView)
        contentStack.setCustomSpacing(14, after: avatarContainer)
        contentStack.setCustomSpacing(42, after: photoActions)
        contentStack.setCustomSpacing(10, after: nicknameLabel)
        contentStack.setCustomSpacing(9, after: underline)
        contentStack.setCustomSpacing(14, after: nicknameRuleLabel)

        [scrollView, contentStack, saveButton].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        view.addSubview(saveButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: saveButton.topAnchor, constant: -12),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 18),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -24),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            avatarContainer.heightAnchor.constraint(equalToConstant: 128),
            imageView.centerXAnchor.constraint(equalTo: avatarContainer.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: avatarContainer.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 128),
            imageView.heightAnchor.constraint(equalToConstant: 128),
            nicknameField.heightAnchor.constraint(equalToConstant: 44),
            underline.heightAnchor.constraint(equalToConstant: 1),
            saveButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            saveButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            saveButton.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12)
        ])
    }

    private func bind() {
        viewModel.onStateChanged = { [weak self] state in self?.apply(state) }
        nicknameField.text = viewModel.state.nickname
        apply(viewModel.state)
    }

    private func apply(_ state: ProfileEditViewModel.State) {
        if let selected = state.selectedThumbnail {
            imageView.image = selected
        } else if state.isAvatarRemoved {
            imageView.image = UIImage(named: "Default_Profile")
        }
        MyPageEditorialStyle.applyPrimaryButtonState(saveButton, isEnabled: state.isSaveEnabled)
        errorLabel.text = state.errorMessage
        errorLabel.isHidden = state.errorMessage == nil
        state.isSaving ? activityIndicator.startAnimating() : activityIndicator.stopAnimating()
        [nicknameField, chooseButton, removeButton].forEach { $0.isEnabled = !state.isSaving }
        removeButton.isHidden = state.remoteAvatarPath == nil &&
            state.selectedThumbnail == nil &&
            state.isAvatarRemoved == false
    }

    private func loadRemoteAvatar(path: String?) {
        guard let path else { return }
        remoteLoadTask = Task { [weak self] in
            guard let self else { return }
            let image = try? await avatarImageManager.loadAvatar(
                for: path,
                maxBytes: 5 * 1024 * 1024
            )
            guard Task.isCancelled == false else { return }
            await MainActor.run {
                if self.viewModel.state.selectedThumbnail == nil &&
                    self.viewModel.state.isAvatarRemoved == false {
                    self.imageView.image = image ?? UIImage(named: "Default_Profile")
                }
            }
        }
    }

    @objc private func nicknameChanged() {
        viewModel.setNickname(nicknameField.text ?? "")
    }

    @objc private func chooseTapped() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func removeTapped() {
        viewModel.removeAvatar()
    }

    @objc private func saveTapped() {
        view.endEditing(true)
        viewModel.saveTapped()
    }
}

extension ProfileEditViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        dismiss(animated: true)
        guard let result = results.first else { return }
        Task { [weak self] in
            guard let self,
                  let pair = try? await mediaProcessor.makePair(from: result, index: 0),
                  let thumbnail = UIImage(data: pair.thumbData) else { return }
            await MainActor.run {
                self.viewModel.setPickedImage(
                    thumbnail: thumbnail,
                    originalFileURL: pair.originalFileURL,
                    sha256: pair.sha256
                )
            }
        }
    }
}
