//
//  UserProfileDetailViewController.swift
//  OutPick
//

import UIKit

@MainActor
final class UserProfileDetailViewController: UIViewController, ChatModalAnimatable {
    private let viewModel: UserProfileDetailViewModel
    private let avatarImageManager: ChatAvatarImageManaging

    private var avatarLoadTask: Task<Void, Never>?
    private var currentAvatarSource = AvatarImageSource()
    private var displayedAvatarImage: UIImage?
    private let avatarThumbnailMaxBytes = 3 * 1024 * 1024
    private let avatarOriginalMaxBytes = 20 * 1024 * 1024

    private lazy var backButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false

        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "chevron.left")
        config.baseForegroundColor = .black
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 4, bottom: 10, trailing: 10)
        button.configuration = config
        button.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        return button
    }()

    private let profileImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 28
        imageView.backgroundColor = .systemGray6
        imageView.image = UIImage(named: "Default_Profile")
        imageView.isUserInteractionEnabled = true
        return imageView
    }()

    private let nicknameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 18, weight: .medium)
        label.textColor = .black
        label.textAlignment = .center
        label.numberOfLines = 2
        return label
    }()

    private let separatorView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemGray4
        return view
    }()

    private let blockIconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .black
        imageView.image = UIImage(
            systemName: "slash.circle",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 34, weight: .regular)
        )
        return imageView
    }()

    private let blockLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .black
        label.textAlignment = .center
        label.text = "차단"
        return label
    }()

    private lazy var blockActionStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [blockIconImageView, blockLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        return stack
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    private lazy var profileStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [profileImageView, nicknameLabel, activityIndicator])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.setCustomSpacing(6, after: profileImageView)
        stack.setCustomSpacing(12, after: nicknameLabel)
        return stack
    }()

    private lazy var actionStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [separatorView, blockActionStack])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 24
        return stack
    }()

    init(
        viewModel: UserProfileDetailViewModel,
        avatarImageManager: ChatAvatarImageManaging
    ) {
        self.viewModel = viewModel
        self.avatarImageManager = avatarImageManager
        super.init(nibName: nil, bundle: nil)
        modalPresentationCapturesStatusBarAppearance = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        avatarLoadTask?.cancel()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .darkContent
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupActions()
        bind()
        viewModel.viewDidLoad()
    }

    private func setupUI() {
        view.backgroundColor = .white

        view.addSubview(backButton)
        view.addSubview(profileStack)
        view.addSubview(actionStack)

        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),

            profileImageView.widthAnchor.constraint(equalToConstant: 112),
            profileImageView.heightAnchor.constraint(equalToConstant: 112),
            separatorView.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -64),
            separatorView.heightAnchor.constraint(equalToConstant: 1),
            blockIconImageView.widthAnchor.constraint(equalToConstant: 34),
            blockIconImageView.heightAnchor.constraint(equalToConstant: 34),

            profileStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            profileStack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor, constant: 24),
            profileStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            profileStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),

            actionStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            actionStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            actionStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            actionStack.topAnchor.constraint(greaterThanOrEqualTo: profileStack.bottomAnchor, constant: 56),
            actionStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -56)
        ])
    }

    private func setupActions() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(profileImageTapped))
        profileImageView.addGestureRecognizer(tapGesture)
    }

    private func bind() {
        viewModel.onStateChanged = { [weak self] state in
            self?.apply(state)
        }
        apply(viewModel.state)
    }

    private func apply(_ state: UserProfileDetailViewModel.State) {
        nicknameLabel.text = state.nickname

        if state.isLoading {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }

        loadAvatarIfNeeded(source: state.avatarSource)
        actionStack.isHidden = state.isCurrentUser
    }

    private func loadAvatarIfNeeded(source: AvatarImageSource) {
        guard currentAvatarSource != source else { return }

        avatarLoadTask?.cancel()
        avatarLoadTask = nil
        currentAvatarSource = source
        showPlaceholderAvatar()

        guard source.hasImagePath else { return }

        avatarLoadTask = Task { [weak self] in
            guard let self else { return }
            await self.loadAvatarProgressively(source: source)
        }
    }

    @objc private func backTapped() {
        viewModel.backTapped()
    }

    @objc private func profileImageTapped() {
        presentAvatarViewerIfPossible()
    }

    private func presentAvatarViewerIfPossible() {
        let avatarSource = viewModel.state.avatarSource
        let initialViewerImage = displayedAvatarImage ?? profileImageView.image
        guard initialViewerImage != nil || avatarSource.hasImagePath else { return }

        let viewer = SimpleImageViewerVC(
            pages: [
                SimpleImageViewerVC.ProgressivePage(
                    initialImage: initialViewerImage,
                    thumbnailImage: nil,
                    thumbnailPath: avatarSource.viewerThumbnailPath,
                    originalPath: avatarSource.viewerOriginalPath,
                    shouldAlwaysResolveThumbnail: avatarSource.hasImagePath
                )
            ],
            startIndex: 0,
            cachedImageProvider: { [weak self] path in
                guard let self else { return nil }
                return await self.avatarImageManager.cachedAvatar(for: path)
            },
            loadImageProvider: { [weak self] path, maxBytes in
                guard let self else { return nil }
                return try? await self.avatarImageManager.loadAvatar(for: path, maxBytes: maxBytes)
            }
        )
        viewer.modalPresentationStyle = .fullScreen
        viewer.modalTransitionStyle = .crossDissolve
        present(viewer, animated: true)
    }

    private func loadAvatarProgressively(source: AvatarImageSource) async {
        if let originalPath = source.originalPath,
           let cachedOriginal = await avatarImageManager.cachedAvatar(for: originalPath) {
            guard !Task.isCancelled, currentAvatarSource == source else { return }
            setDisplayedAvatar(cachedOriginal)
            return
        }

        if let immediatePath = source.immediateDisplayPath {
            let immediateMaxBytes = source.thumbnailPath != nil
                ? avatarThumbnailMaxBytes
                : avatarOriginalMaxBytes

            if let cachedImmediate = await avatarImageManager.cachedAvatar(for: immediatePath) {
                guard !Task.isCancelled, currentAvatarSource == source else { return }
                setDisplayedAvatar(cachedImmediate)
            } else if let immediateImage = try? await avatarImageManager.loadAvatar(
                for: immediatePath,
                maxBytes: immediateMaxBytes
            ) {
                guard !Task.isCancelled, currentAvatarSource == source else { return }
                setDisplayedAvatar(immediateImage)
            }
        }

        guard let originalPath = source.upgradeOriginalPath else { return }

        if let originalImage = try? await avatarImageManager.loadAvatar(
            for: originalPath,
            maxBytes: avatarOriginalMaxBytes
        ) {
            guard !Task.isCancelled, currentAvatarSource == source else { return }
            setDisplayedAvatar(originalImage)
        }
    }

    private func showPlaceholderAvatar() {
        profileImageView.image = UIImage(named: "Default_Profile")
        displayedAvatarImage = nil
    }

    private func setDisplayedAvatar(_ image: UIImage) {
        profileImageView.image = image
        displayedAvatarImage = image
    }
}
