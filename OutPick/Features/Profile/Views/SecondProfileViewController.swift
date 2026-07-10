//
//  SecondProfileViewController.swift
//  OutPick
//

import UIKit
import PhotosUI

final class SecondProfileViewController: UIViewController {

    private let viewModel: SecondProfileViewModel
    private let mediaProcessor: MediaProcessingServiceProtocol

    // VC 레벨에서 마지막 선택을 기억(복귀 시 복원용)
    private var lastPickedOriginalPath: String?
    private var lastPickedSHA: String?
    private var isSaving = false
    private var didSaveDraftForExplicitBack = false

    // MARK: - UI (Header)

    private let backButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        b.contentHorizontalAlignment = .leading
        return b
    }()


    // MARK: - UI (Form)

    private let nicknameGuideLabel: UILabel = {
        let l = UILabel()
        l.text = "사용할 닉네임을 설정해 주세요"
        l.font = .systemFont(ofSize: 13, weight: .regular)
        l.textColor = OutPickTheme.ColorToken.textSecondary
        l.numberOfLines = 0
        return l
    }()

    private let photoGuideLabel: UILabel = {
        let l = UILabel()
        l.text = "사용할 대표 프로필 사진을 선택해 주세요"
        l.font = .systemFont(ofSize: 13, weight: .regular)
        l.textColor = OutPickTheme.ColorToken.textSecondary
        l.numberOfLines = 0
        return l
    }()

    private let nicknameField: UITextField = {
        let tf = UITextField()
        tf.placeholder = "닉네임 (최대 20자)"
        tf.borderStyle = .none
        tf.backgroundColor = OutPickTheme.ColorToken.surfaceBase
        tf.textColor = OutPickTheme.ColorToken.textPrimary
        tf.tintColor = OutPickTheme.ColorToken.accent
        tf.layer.cornerRadius = 10
        tf.layer.borderWidth = 1
        tf.layer.borderColor = OutPickTheme.ColorToken.borderSubtle.cgColor
        let leftPadding = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        let rightPadding = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        tf.leftView = leftPadding
        tf.leftViewMode = .always
        tf.rightView = rightPadding
        tf.rightViewMode = .always
        tf.attributedPlaceholder = NSAttributedString(
            string: "닉네임 (최대 20자)",
            attributes: [.foregroundColor: OutPickTheme.ColorToken.textTertiary]
        )
        tf.autocapitalizationType = .none
        tf.autocorrectionType = .no
        tf.returnKeyType = .done
        return tf
    }()

    private let countLabel: UILabel = {
        let l = UILabel()
        l.text = "0 / 20"
        l.font = .systemFont(ofSize: 12, weight: .regular)
        l.textColor = OutPickTheme.ColorToken.textSecondary
        l.textAlignment = .right
        return l
    }()

    private let profileImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 15
        iv.backgroundColor = OutPickTheme.ColorToken.surfaceBase
        iv.image = UIImage(named: "Default_Profile")
        iv.isUserInteractionEnabled = true
        return iv
    }()

    private let addImageButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "plus.circle.fill"), for: .normal)
        b.tintColor = OutPickTheme.ColorToken.accent
        return b
    }()

    private let removeImageButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "minus.circle.fill"), for: .normal)
        b.tintColor = OutPickTheme.ColorToken.destructive
        b.isHidden = true
        return b
    }()

    private let errorLabel: UILabel = {
        let l = UILabel()
        l.textColor = OutPickTheme.ColorToken.destructive
        l.numberOfLines = 0
        l.font = .systemFont(ofSize: 13, weight: .regular)
        l.isHidden = true
        return l
    }()

    private let completeButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("완료 2/2", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        b.layer.cornerRadius = 12
        b.backgroundColor = OutPickTheme.ColorToken.surfaceElevated
        b.setTitleColor(OutPickTheme.ColorToken.textDisabled, for: .normal)
        b.isEnabled = false
        b.alpha = 0.5
        return b
    }()

    private let activity: UIActivityIndicatorView = {
        let a = UIActivityIndicatorView(style: .large)
        a.color = OutPickTheme.ColorToken.accent
        a.hidesWhenStopped = true
        return a
    }()

    // MARK: - Init

    init(
        viewModel: SecondProfileViewModel,
        mediaProcessor: MediaProcessingServiceProtocol = DefaultMediaProcessingService()
    ) {
        self.viewModel = viewModel
        self.mediaProcessor = mediaProcessor
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = OutPickTheme.ColorToken.backgroundBase

        installKeyboardDismissTapGesture()
        backButton.tintColor = OutPickTheme.ColorToken.accent
        backButton.setTitleColor(OutPickTheme.ColorToken.accent, for: .normal)

        setupUI()
        bind()
        restoreDraftFromUserDefaultsIfNeeded()

        // 액션
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        addImageButton.addTarget(self, action: #selector(addImageTapped), for: .touchUpInside)
        // 이미지뷰를 탭해도 사진 선택 가능
        let tap = UITapGestureRecognizer(target: self, action: #selector(addImageTapped))
        profileImageView.addGestureRecognizer(tap)
        removeImageButton.addTarget(self, action: #selector(removeImageTapped), for: .touchUpInside)
        completeButton.addTarget(self, action: #selector(completeTapped), for: .touchUpInside)

        nicknameField.addTarget(self, action: #selector(nicknameChanged), for: .editingChanged)
        nicknameField.delegate = self
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateInteractivePopGestureAvailability()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveDraftAfterCompletedPopIfNeeded()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        guard let navigationController else { return }
        if navigationController.topViewController !== self {
            navigationController.interactivePopGestureRecognizer?.isEnabled = true
        }
    }

    // MARK: - Bind

    private func bind() {
        viewModel.onStateChanged = { [weak self] state in
            guard let self else { return }
            self.apply(state)
        }
    }

    private func apply(_ state: SecondProfileViewModel.State) {
        isSaving = state.isSaving
        updateInteractivePopGestureAvailability()

        countLabel.text = state.nicknameCountText

        // 완료 버튼
        completeButton.isEnabled = state.isCompleteEnabled
        completeButton.alpha = state.isCompleteEnabled ? 1.0 : 0.5
        completeButton.backgroundColor = state.isCompleteEnabled
            ? OutPickTheme.ColorToken.accent
            : OutPickTheme.ColorToken.surfaceElevated
        completeButton.setTitleColor(
            state.isCompleteEnabled ? OutPickTheme.ColorToken.backgroundBase : OutPickTheme.ColorToken.textDisabled,
            for: .normal
        )

        // 에러
        if let msg = state.errorMessage, !msg.isEmpty {
            errorLabel.text = msg
            errorLabel.isHidden = false
        } else {
            errorLabel.text = nil
            errorLabel.isHidden = true
        }

        // 이미지
        if let thumb = state.selectedThumb {
            profileImageView.image = thumb
            // ✅ 이미지가 있으면 제거 버튼 노출
            removeImageButton.isHidden = false
        } else {
            profileImageView.image = UIImage(named: "Default_Profile")
            removeImageButton.isHidden = true
        }

        // 저장 중 UI
        if state.isSaving {
            completeButton.setTitle("완료 2/2", for: .normal)
            completeButton.isEnabled = false
            completeButton.alpha = 1.0
            completeButton.backgroundColor = OutPickTheme.ColorToken.accent
            view.bringSubviewToFront(activity)
            activity.startAnimating()
        } else {
            activity.stopAnimating()
            completeButton.setTitle("완료 2/2", for: .normal)
        }
    }

    // MARK: - UI Layout

    private func setupUI() {
        // headerStack: backButton + spacer (상단은 심플하게)
        let spacer = UIView()
        let header = UIStackView(arrangedSubviews: [backButton, spacer])
        header.axis = .horizontal
        header.alignment = .center
        header.distribution = .fill
        header.spacing = 8

        // 폭 우선순위: 왼쪽(뒤로), 나머지는 spacer
        backButton.setContentHuggingPriority(.required, for: .horizontal)
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // 프로필 이미지 + overlay 버튼
        let imageContainer = UIView()
        imageContainer.translatesAutoresizingMaskIntoConstraints = false
        imageContainer.clipsToBounds = false
        imageContainer.addSubview(profileImageView)

        profileImageView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            imageContainer.widthAnchor.constraint(equalToConstant: 120),
            imageContainer.heightAnchor.constraint(equalToConstant: 120),

            profileImageView.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor),
            profileImageView.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor),
            profileImageView.topAnchor.constraint(equalTo: imageContainer.topAnchor),
            profileImageView.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor),
            profileImageView.widthAnchor.constraint(equalToConstant: 120),
            profileImageView.heightAnchor.constraint(equalToConstant: 120)
        ])

        let photoSection = UIStackView(arrangedSubviews: [photoGuideLabel, imageContainer])
        photoSection.axis = .vertical
        photoSection.spacing = 10
        photoSection.alignment = .leading

        let nicknameSection = UIStackView(arrangedSubviews: [nicknameGuideLabel, nicknameField, countLabel])
        nicknameSection.axis = .vertical
        nicknameSection.spacing = 8
        nicknameSection.alignment = .fill
        nicknameField.heightAnchor.constraint(equalToConstant: 48).isActive = true

        // 메인 스택
        let stack = UIStackView(arrangedSubviews: [
            header,
            nicknameSection,
            photoSection,
            errorLabel
        ])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill

        // 닉네임 섹션과 사진 섹션 사이만 더 넓게
        stack.setCustomSpacing(56, after: nicknameSection)

        // 하단 고정: 완료 버튼(단일) — 컨테이너 없이 safe area에 직접 고정

        // ✅ 버튼 내부 패딩(터치 영역/가독성)
        completeButton.contentEdgeInsets = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)

        view.addSubview(completeButton)
        view.addSubview(activity)

        completeButton.translatesAutoresizingMaskIntoConstraints = false
        activity.translatesAutoresizingMaskIntoConstraints = false

        // 스크롤(내용) + 하단 고정(완료 버튼)
        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = true

        let contentView = UIView()

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(stack)
        view.addSubview(addImageButton)
        view.addSubview(removeImageButton)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addImageButton.translatesAutoresizingMaskIntoConstraints = false
        removeImageButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            // scrollView 영역: 위 ~ 하단 버튼 위
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: completeButton.topAnchor, constant: -12),

            // contentView: scrollView content layout
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),

            // contentView 폭 고정(가로 스크롤 방지)
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            // stack: contentView 안쪽 여백
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),

            // 하단 완료 버튼 고정
            completeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            completeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            completeButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
            completeButton.heightAnchor.constraint(equalToConstant: 52),

            activity.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activity.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            addImageButton.centerXAnchor.constraint(equalTo: profileImageView.trailingAnchor),
            addImageButton.centerYAnchor.constraint(equalTo: profileImageView.bottomAnchor),
            addImageButton.widthAnchor.constraint(equalToConstant: 30),
            addImageButton.heightAnchor.constraint(equalToConstant: 30),

            removeImageButton.centerXAnchor.constraint(equalTo: profileImageView.leadingAnchor),
            removeImageButton.centerYAnchor.constraint(equalTo: profileImageView.bottomAnchor),
            removeImageButton.widthAnchor.constraint(equalToConstant: 30),
            removeImageButton.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    // MARK: - Actions

    @objc private func backTapped() {
        saveDraftToUserDefaults()
        didSaveDraftForExplicitBack = true
        viewModel.backTapped()
    }

    @objc private func nicknameChanged() {
        viewModel.setNickname(nicknameField.text ?? "")
        saveDraftToUserDefaults()
    }

    @objc private func completeTapped() {
        viewModel.completeTapped()
    }

    @objc private func removeImageTapped() {
        viewModel.clearImage()
        lastPickedOriginalPath = nil
        lastPickedSHA = nil
        saveDraftToUserDefaults()
    }

    @objc private func addImageTapped() {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    func clearDraftCacheAfterCompletion() {
        clearDraftFromUserDefaults()
    }

    static func clearDraftCache() {
        UserDefaults.standard.removeObject(forKey: draftKey)
    }
    
    // MARK: - Draft Persistence (UserDefaults)

    private struct DraftCache: Codable {
        var nickname: String
        var thumbBase64: String?
        var originalPath: String?
        var sha: String?
    }

    private static let draftKey = "OutPick.SecondProfile.Draft"

    private func saveDraftToUserDefaults() {
        let nickname = nicknameField.text ?? ""

        var thumbBase64: String? = nil
        if let img = profileImageView.image,
           !removeImageButton.isHidden,
           let data = img.jpegData(compressionQuality: 0.8) {
            thumbBase64 = data.base64EncodedString()
        }

        // VM에 저장된 값이 없다면(현재 파일만으로는 접근 불가) VC에서 마지막 선택값을 기억할 수 있도록
        // picker에서 setPickedImage 호출 시 함께 저장하는 방식으로 처리합니다.
        let cache = DraftCache(
            nickname: nickname,
            thumbBase64: thumbBase64,
            originalPath: lastPickedOriginalPath,
            sha: lastPickedSHA
        )

        if let encoded = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(encoded, forKey: Self.draftKey)
        }
    }

    private func restoreDraftFromUserDefaultsIfNeeded() {
        guard let data = UserDefaults.standard.data(forKey: Self.draftKey),
              let cache = try? JSONDecoder().decode(DraftCache.self, from: data)
        else { return }

        // 닉네임
        if !cache.nickname.isEmpty {
            nicknameField.text = cache.nickname
            // ✅ 복귀 직후에도 글자 수 UI가 즉시 반영되도록
            countLabel.text = "\(cache.nickname.count) / 20"
            viewModel.setNickname(cache.nickname)
        }

        // 이미지(있으면)
        if let b64 = cache.thumbBase64,
           let d = Data(base64Encoded: b64),
           let img = UIImage(data: d),
           let path = cache.originalPath,
           let sha = cache.sha {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                clearDraftFromUserDefaults()
                return
            }

            profileImageView.image = img
            removeImageButton.isHidden = false
            lastPickedOriginalPath = path
            lastPickedSHA = sha
            viewModel.setPickedImage(thumb: img, originalFileURL: url, sha: sha)
        }
    }

    private func clearDraftFromUserDefaults() {
        UserDefaults.standard.removeObject(forKey: Self.draftKey)
    }

    private func updateInteractivePopGestureAvailability() {
        navigationController?.interactivePopGestureRecognizer?.isEnabled = !isSaving
    }

    private func saveDraftAfterCompletedPopIfNeeded() {
        guard isMovingFromParent || navigationController?.viewControllers.contains(self) == false else {
            return
        }

        guard !didSaveDraftForExplicitBack else {
            didSaveDraftForExplicitBack = false
            return
        }

        guard let transitionCoordinator else {
            saveDraftToUserDefaults()
            return
        }

        transitionCoordinator.animate(alongsideTransition: nil) { [weak self] context in
            guard let self, !context.isCancelled else { return }
            self.saveDraftToUserDefaults()
        }
    }
}

// MARK: - UITextFieldDelegate

extension SecondProfileViewController: UITextFieldDelegate {

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        // 20자 제한(입력 단계에서 1차 방어)
        let current = textField.text ?? ""
        guard let r = Range(range, in: current) else { return true }
        let next = current.replacingCharacters(in: r, with: string)
        return next.count <= 20
    }
}

// MARK: - PHPickerViewControllerDelegate

extension SecondProfileViewController: PHPickerViewControllerDelegate {

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        dismiss(animated: true)

        guard let first = results.first else { return }

        Task { [weak self] in
            guard let self else { return }
            do {
                // pair 생성(thumbData + originalURL + sha256)
                let pair = try await mediaProcessor.makePair(from: first, index: 0)

                // thumbData -> UIImage
                guard let thumb = UIImage(data: pair.thumbData) else { return }

                // VM에 전달
                await MainActor.run {
                    self.lastPickedOriginalPath = pair.originalFileURL.path
                    self.lastPickedSHA = pair.sha256

                    self.viewModel.setPickedImage(
                        thumb: thumb,
                        originalFileURL: pair.originalFileURL,
                        sha: pair.sha256
                    )

                    self.saveDraftToUserDefaults()
                }
            } catch {
                // 필요하면 에러 메시지 표시로 연결 가능
                // 여기서는 조용히 무시(UX 정책에 따라 변경)
            }
        }
    }
}
