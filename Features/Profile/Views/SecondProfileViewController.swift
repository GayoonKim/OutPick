//
//  SecondProfileViewController.swift
//  OutPick
//

import UIKit
import PhotosUI

final class SecondProfileViewController: UIViewController {

    private let viewModel: SecondProfileViewModel

    // VC 레벨에서 마지막 선택을 기억(복귀 시 복원용)
    private var lastPickedOriginalPath: String?
    private var lastPickedSHA: String?

    // MARK: - UI (Header)

    private let backButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        b.setTitle(" 이전", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        b.contentHorizontalAlignment = .leading
        return b
    }()


    // MARK: - UI (Form)

    private let nicknameGuideLabel: UILabel = {
        let l = UILabel()
        l.text = "사용할 닉네임을 설정해 주세요"
        l.font = .systemFont(ofSize: 13, weight: .regular)
        l.textColor = .secondaryLabel
        l.numberOfLines = 0
        return l
    }()

    private let photoGuideLabel: UILabel = {
        let l = UILabel()
        l.text = "사용할 대표 프로필 사진을 선택해 주세요"
        l.font = .systemFont(ofSize: 13, weight: .regular)
        l.textColor = .secondaryLabel
        l.numberOfLines = 0
        return l
    }()

    private let nicknameField: UITextField = {
        let tf = UITextField()
        tf.placeholder = "닉네임 (최대 20자)"
        tf.borderStyle = .roundedRect
        tf.autocapitalizationType = .none
        tf.autocorrectionType = .no
        tf.returnKeyType = .done
        return tf
    }()

    private let countLabel: UILabel = {
        let l = UILabel()
        l.text = "0 / 20"
        l.font = .systemFont(ofSize: 12, weight: .regular)
        l.textColor = .secondaryLabel
        l.textAlignment = .right
        return l
    }()

    private let profileImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 48
        iv.backgroundColor = .secondarySystemBackground
        iv.image = UIImage(systemName: "person.circle")
        iv.tintColor = .secondaryLabel
        iv.isUserInteractionEnabled = true
        return iv
    }()

    private let addImageButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("사진 추가", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        return b
    }()

    private let removeImageButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("제거", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        b.isHidden = true
        return b
    }()

    private let errorLabel: UILabel = {
        let l = UILabel()
        l.textColor = .systemRed
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
        b.backgroundColor = .label
        b.setTitleColor(.systemBackground, for: .normal)
        b.isEnabled = false
        b.alpha = 0.5
        return b
    }()

    private let activity: UIActivityIndicatorView = {
        let a = UIActivityIndicatorView(style: .medium)
        a.hidesWhenStopped = true
        return a
    }()

    // MARK: - Init

    init(viewModel: SecondProfileViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        // 색상(검정)
        backButton.tintColor = .label
        backButton.setTitleColor(.label, for: .normal)
        addImageButton.setTitleColor(.label, for: .normal)
        removeImageButton.setTitleColor(.label, for: .normal)

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

    // MARK: - Bind

    private func bind() {
        viewModel.onStateChanged = { [weak self] state in
            guard let self else { return }
            self.apply(state)
        }
    }

    private func apply(_ state: SecondProfileViewModel.State) {
        countLabel.text = state.nicknameCountText

        // 완료 버튼
        completeButton.isEnabled = state.isCompleteEnabled
        completeButton.alpha = state.isCompleteEnabled ? 1.0 : 0.5

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
            profileImageView.tintColor = nil
            // ✅ 이미지가 있으면 제거 버튼 노출
            removeImageButton.isHidden = false
        } else {
            profileImageView.image = UIImage(systemName: "person.circle")
            profileImageView.tintColor = .secondaryLabel
            removeImageButton.isHidden = true
        }

        // 저장 중 UI
        if state.isSaving {
            activity.startAnimating()
            completeButton.setTitle("저장 중...", for: .normal)
            completeButton.isEnabled = false
            completeButton.alpha = 0.6
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

        // 프로필 이미지 + 버튼
        profileImageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            profileImageView.widthAnchor.constraint(equalToConstant: 96),
            profileImageView.heightAnchor.constraint(equalToConstant: 96)
        ])

        let imageButtons = UIStackView(arrangedSubviews: [addImageButton, removeImageButton])
        imageButtons.axis = .horizontal
        imageButtons.spacing = 12
        imageButtons.alignment = .leading
        imageButtons.distribution = .fillProportionally

        let imageSection = UIStackView(arrangedSubviews: [profileImageView, imageButtons])
        imageSection.axis = .vertical
        imageSection.spacing = 10
        imageSection.alignment = .leading

        let photoSection = UIStackView(arrangedSubviews: [photoGuideLabel, imageSection])
        photoSection.axis = .vertical
        photoSection.spacing = 10
        photoSection.alignment = .leading

        // 닉네임 + 카운트
        let nicknameRow = UIStackView(arrangedSubviews: [nicknameField, countLabel])
        nicknameRow.axis = .horizontal
        nicknameRow.alignment = .center
        nicknameRow.spacing = 10
        countLabel.widthAnchor.constraint(equalToConstant: 60).isActive = true

        let nicknameSection = UIStackView(arrangedSubviews: [nicknameGuideLabel, nicknameRow])
        nicknameSection.axis = .vertical
        nicknameSection.spacing = 8
        nicknameSection.alignment = .fill

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

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false

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

            activity.centerYAnchor.constraint(equalTo: completeButton.centerYAnchor),
            activity.trailingAnchor.constraint(equalTo: completeButton.trailingAnchor, constant: -16)
        ])
    }

    // MARK: - Actions

    @objc private func backTapped() {
        saveDraftToUserDefaults()
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
           img != UIImage(systemName: "person.circle"),
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
           let img = UIImage(data: d) {
            profileImageView.image = img
            profileImageView.tintColor = nil
            // ✅ 썸네일만 복원되어도 사용자가 제거할 수 있어야 함
            removeImageButton.isHidden = false

            if let path = cache.originalPath,
               let sha = cache.sha {
                let url = URL(fileURLWithPath: path)
                if FileManager.default.fileExists(atPath: url.path) {
                    viewModel.setPickedImage(thumb: img, originalFileURL: url, sha: sha)
                }
            }
        }
    }

    private func clearDraftFromUserDefaults() {
        UserDefaults.standard.removeObject(forKey: Self.draftKey)
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
                let pair = try await MediaManager.shared.makePair(from: first, index: 0)

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
