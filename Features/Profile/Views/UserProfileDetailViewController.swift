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
    private var currentAvatarPath: String?

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

        loadAvatarIfNeeded(path: state.avatarPath)
    }

    private func loadAvatarIfNeeded(path: String?) {
        guard currentAvatarPath != path else { return }

        avatarLoadTask?.cancel()
        avatarLoadTask = nil
        currentAvatarPath = path
        profileImageView.image = UIImage(named: "Default_Profile")

        guard let path, !path.isEmpty else { return }

        avatarLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }

            if let cached = await self.avatarImageManager.cachedAvatar(for: path) {
                guard !Task.isCancelled, self.currentAvatarPath == path else { return }
                self.profileImageView.image = cached
                return
            }

            do {
                let image = try await self.avatarImageManager.loadAvatar(for: path, maxBytes: 3 * 1024 * 1024)
                guard !Task.isCancelled, self.currentAvatarPath == path else { return }
                self.profileImageView.image = image
            } catch {
                guard !Task.isCancelled, self.currentAvatarPath == path else { return }
                self.profileImageView.image = UIImage(named: "Default_Profile")
            }
        }
    }

    @objc private func backTapped() {
        viewModel.backTapped()
    }
}
