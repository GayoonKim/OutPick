import PhotosUI
import UIKit

final class AvatarSetupViewController: UIViewController {
    private let viewModel: AvatarSetupViewModel
    private let mediaProcessor: MediaProcessingServiceProtocol

    private let backgroundImageView = UIImageView()
    private let backgroundBlurView = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemUltraThinMaterialDark)
    )
    private let backgroundScrim = UIView()
    private let backButton = UIButton(type: .system)
    private let headerView = OnboardingEditorialHeaderView()
    private let profileImageView = UIImageView()
    private let chooseButton = UIButton(type: .system)
    private let removeButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let skipButton = UIButton(type: .system)

    init(
        viewModel: AvatarSetupViewModel,
        mediaProcessor: MediaProcessingServiceProtocol = DefaultMediaProcessingService()
    ) {
        self.viewModel = viewModel
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
    }

    private func configureUI() {
        view.backgroundColor = OutPickTheme.ColorToken.backgroundBase

        backgroundImageView.contentMode = .scaleAspectFill
        backgroundImageView.clipsToBounds = true
        backgroundImageView.alpha = 0
        backgroundBlurView.isHidden = true
        backgroundScrim.backgroundColor = OutPickTheme.ColorToken.backgroundBase.withAlphaComponent(0.68)

        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.tintColor = OutPickTheme.ColorToken.textPrimary
        backButton.accessibilityLabel = "이전"
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        headerView.configure(
            step: "02 / 03",
            title: "프로필 사진을\n추가해 볼까요",
            subtitle: "나를 보여줄 사진을 골라주세요\n나중에 언제든 바꿀 수 있어요"
        )

        profileImageView.image = UIImage(named: "Default_Profile")
        profileImageView.backgroundColor = OutPickTheme.ColorToken.surfaceBase
        profileImageView.contentMode = .scaleAspectFill
        profileImageView.clipsToBounds = true
        profileImageView.layer.cornerRadius = 110
        profileImageView.layer.borderWidth = 1
        profileImageView.layer.borderColor = OutPickTheme.ColorToken.borderStrong.cgColor
        profileImageView.isUserInteractionEnabled = true
        profileImageView.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(chooseTapped))
        )

        var chooseConfiguration = UIButton.Configuration.plain()
        chooseConfiguration.title = "사진 선택"
        chooseConfiguration.image = UIImage(systemName: "photo")
        chooseConfiguration.imagePadding = 8
        chooseConfiguration.baseForegroundColor = OutPickTheme.ColorToken.textPrimary
        chooseButton.configuration = chooseConfiguration
        chooseButton.addTarget(self, action: #selector(chooseTapped), for: .touchUpInside)

        removeButton.setTitle("선택 해제", for: .normal)
        removeButton.setTitleColor(OutPickTheme.ColorToken.textSecondary, for: .normal)
        removeButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        removeButton.addTarget(self, action: #selector(removeTapped), for: .touchUpInside)

        nextButton.setTitle("다음", for: .normal)
        nextButton.titleLabel?.font = .boldSystemFont(ofSize: 16)
        nextButton.layer.cornerRadius = 14
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)

        skipButton.setTitle("건너뛰기", for: .normal)
        skipButton.setTitleColor(OutPickTheme.ColorToken.textSecondary, for: .normal)
        skipButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)

        [
            backgroundImageView, backgroundBlurView, backgroundScrim, backButton, headerView,
            profileImageView, chooseButton, removeButton, nextButton, skipButton
        ].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            backgroundImageView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            backgroundBlurView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundBlurView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundBlurView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundBlurView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            backgroundScrim.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundScrim.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundScrim.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundScrim.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),

            headerView.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 8),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            profileImageView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 24),
            profileImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            profileImageView.widthAnchor.constraint(equalToConstant: 220),
            profileImageView.heightAnchor.constraint(equalToConstant: 220),

            chooseButton.topAnchor.constraint(equalTo: profileImageView.bottomAnchor, constant: 18),
            chooseButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            removeButton.topAnchor.constraint(equalTo: chooseButton.bottomAnchor, constant: 2),
            removeButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            removeButton.bottomAnchor.constraint(lessThanOrEqualTo: skipButton.topAnchor, constant: -18),

            nextButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            nextButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            nextButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -52),
            nextButton.heightAnchor.constraint(equalToConstant: 54),

            skipButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            skipButton.topAnchor.constraint(equalTo: nextButton.bottomAnchor, constant: 8),
            skipButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    private func bind() {
        viewModel.onStateChanged = { [weak self] state in
            self?.apply(state, animated: true)
        }
        apply(viewModel.state, animated: false)
    }

    private func apply(_ state: AvatarSetupViewModel.State, animated: Bool) {
        let image = state.selectedThumbnail ?? UIImage(named: "Default_Profile")
        let changes = {
            self.profileImageView.image = image
            self.backgroundImageView.image = state.selectedThumbnail
            self.backgroundImageView.alpha = state.selectedThumbnail == nil ? 0 : 0.32
            self.backgroundBlurView.isHidden = state.selectedThumbnail == nil
            self.removeButton.isHidden = state.selectedThumbnail == nil
            self.nextButton.isEnabled = state.isNextEnabled
            self.nextButton.backgroundColor = state.isNextEnabled
                ? OutPickTheme.ColorToken.accent
                : OutPickTheme.ColorToken.surfaceElevated
            self.nextButton.setTitleColor(
                state.isNextEnabled
                    ? OutPickTheme.ColorToken.backgroundBase
                    : OutPickTheme.ColorToken.textDisabled,
                for: .normal
            )
        }

        guard animated, UIAccessibility.isReduceMotionEnabled == false else {
            changes()
            return
        }
        UIView.transition(
            with: profileImageView,
            duration: 0.3,
            options: [.transitionCrossDissolve, .beginFromCurrentState],
            animations: changes
        )
    }

    @objc private func backTapped() {
        viewModel.backTapped()
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
        viewModel.clearImage()
    }

    @objc private func nextTapped() {
        viewModel.nextTapped()
    }

    @objc private func skipTapped() {
        viewModel.skipTapped()
    }
}

extension AvatarSetupViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        dismiss(animated: true)
        guard let result = results.first else { return }

        Task { [weak self] in
            guard let self,
                  let pair = try? await mediaProcessor.makePair(from: result, index: 0),
                  let thumbnail = UIImage(data: pair.thumbData) else {
                return
            }
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
