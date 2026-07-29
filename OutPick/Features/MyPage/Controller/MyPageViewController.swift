import FirebaseAuth
import GoogleSignIn
import KakaoSDKCommon
import KakaoSDKUser
import UIKit

final class MyPageViewController: UIViewController {
    private let viewModel: MyPageViewModel
    private let avatarImageManager: AvatarImageManaging
    private let customNavigationBar = CustomNavigationBarView()
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let editorialHeader = MyPageEditorialHeaderView()
    private let identityRow = UIStackView()
    private let profileImageView = UIImageView()
    private let nicknameLabel = UILabel()
    private let moodSectionLabel = UILabel()
    private let moodChipsView = MyPageMoodChipsView()
    private let actionSectionLabel = UILabel()
    private let editProfileButton = MyPageActionRowButton(
        title: "프로필 편집",
        subtitle: "닉네임과 프로필 이미지를 관리해요"
    )
    private let editStylesButton = MyPageActionRowButton(
        title: "관심 스타일",
        subtitle: "내 취향을 보여주는 스타일을 골라요"
    )
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let errorLabel = UILabel()
    private var avatarLoadTask: Task<Void, Never>?
    private var didRouteToLogin = false

    init(
        viewModel: MyPageViewModel,
        avatarImageManager: AvatarImageManaging
    ) {
        self.viewModel = viewModel
        self.avatarImageManager = avatarImageManager
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        avatarLoadTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        bind()
        viewModel.load()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    private func configureUI() {
        view.backgroundColor = OutPickTheme.ColorToken.backgroundBase
        customNavigationBar.configureForMyPage(menu: makeSettingsMenu())

        editorialHeader.configure(
            eyebrow: "MY OUTPICK",
            title: "나의 취향을\n한눈에",
            subtitle: "프로필과 관심 스타일을 관리해요"
        )

        profileImageView.image = UIImage(named: "Default_Profile")
        profileImageView.contentMode = .scaleAspectFill
        profileImageView.clipsToBounds = true
        profileImageView.layer.cornerRadius = 50
        profileImageView.layer.borderWidth = 1
        profileImageView.layer.borderColor = OutPickTheme.ColorToken.borderStrong.cgColor
        profileImageView.backgroundColor = OutPickTheme.ColorToken.surfaceBase
        profileImageView.isAccessibilityElement = true
        profileImageView.accessibilityLabel = "프로필 이미지"

        nicknameLabel.font = MyPageEditorialStyle.serifFont(size: 32, weight: .bold)
        nicknameLabel.textColor = OutPickTheme.ColorToken.textPrimary
        nicknameLabel.numberOfLines = 2
        nicknameLabel.adjustsFontForContentSizeCategory = true

        configureSectionLabel(moodSectionLabel, text: "MY STYLE")
        configureSectionLabel(actionSectionLabel, text: "EDIT")

        editProfileButton.addTarget(self, action: #selector(editProfileTapped), for: .touchUpInside)
        editStylesButton.addTarget(self, action: #selector(editStylesTapped), for: .touchUpInside)

        activityIndicator.color = OutPickTheme.ColorToken.accent
        errorLabel.font = .systemFont(ofSize: 13)
        errorLabel.textColor = OutPickTheme.ColorToken.destructive
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0

        identityRow.axis = .horizontal
        identityRow.spacing = 20
        identityRow.alignment = .center
        identityRow.addArrangedSubview(profileImageView)
        identityRow.addArrangedSubview(nicknameLabel)

        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 0
        [
            editorialHeader, identityRow, moodSectionLabel, moodChipsView,
            actionSectionLabel, editProfileButton, editStylesButton,
            activityIndicator, errorLabel
        ].forEach(stackView.addArrangedSubview)
        profileImageView.widthAnchor.constraint(equalToConstant: 100).isActive = true
        profileImageView.heightAnchor.constraint(equalToConstant: 100).isActive = true
        stackView.setCustomSpacing(34, after: editorialHeader)
        stackView.setCustomSpacing(42, after: identityRow)
        stackView.setCustomSpacing(14, after: moodSectionLabel)
        stackView.setCustomSpacing(42, after: moodChipsView)
        stackView.setCustomSpacing(5, after: actionSectionLabel)
        stackView.setCustomSpacing(20, after: editStylesButton)

        [customNavigationBar, scrollView, stackView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.delaysContentTouches = false
        view.addSubview(customNavigationBar)
        view.addSubview(scrollView)
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            customNavigationBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            customNavigationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            customNavigationBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: customNavigationBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 26),
            stackView.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -24),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -36)
        ])

        animateEntranceIfNeeded()
    }

    private func configureSectionLabel(_ label: UILabel, text: String) {
        label.text = text
        label.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        label.textColor = OutPickTheme.ColorToken.accent
        label.adjustsFontForContentSizeCategory = true
    }

    private func animateEntranceIfNeeded() {
        guard UIAccessibility.isReduceMotionEnabled == false else { return }
        [editorialHeader, identityRow, moodChipsView].enumerated().forEach { index, view in
            view.alpha = 0
            view.transform = CGAffineTransform(translationX: 0, y: 12)
            UIView.animate(
                withDuration: 0.38,
                delay: Double(index) * 0.07,
                options: [.curveEaseOut]
            ) {
                view.alpha = 1
                view.transform = .identity
            }
        }
    }

    private func bind() {
        viewModel.onStateChanged = { [weak self] state in self?.apply(state) }
        apply(viewModel.state)
    }

    private func apply(_ state: MyPageViewModel.State) {
        nicknameLabel.text = state.nickname
        moodChipsView.apply(names: state.selectedMoodNames)
        errorLabel.text = state.errorMessage
        errorLabel.isHidden = state.errorMessage == nil
        state.isLoading ? activityIndicator.startAnimating() : activityIndicator.stopAnimating()
        loadAvatar(path: state.avatarPath)
    }

    private func loadAvatar(path: String?) {
        avatarLoadTask?.cancel()
        guard let path, !path.isEmpty else {
            profileImageView.image = UIImage(named: "Default_Profile")
            return
        }
        avatarLoadTask = Task { [weak self] in
            guard let self else { return }
            let image = try? await avatarImageManager.loadAvatar(
                for: path,
                maxBytes: 5 * 1024 * 1024
            )
            guard Task.isCancelled == false else { return }
            await MainActor.run {
                self.profileImageView.image = image ?? UIImage(named: "Default_Profile")
            }
        }
    }

    @objc private func editProfileTapped() {
        viewModel.editProfileTapped()
    }

    @objc private func editStylesTapped() {
        viewModel.editStylesTapped()
    }

    private func makeSettingsMenu() -> UIMenu {
        UIMenu(children: [
            UIAction(
                title: "로그아웃",
                image: UIImage(systemName: "rectangle.portrait.and.arrow.right")
            ) { [weak self] _ in
                self?.logOut()
            },
            UIAction(
                title: "계정 삭제",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.viewModel.deleteAccountTapped()
            }
        ])
    }

    private func logOut() {
        LoginManager.shared.logout()
        try? Auth.auth().signOut()
        GIDSignIn.sharedInstance.signOut()
        UserApi.shared.logout { [weak self] _ in
            Task { @MainActor in self?.routeToLoginOnce() }
        }
    }

    @MainActor
    private func routeToLoginOnce() {
        guard didRouteToLogin == false else { return }
        didRouteToLogin = true
        AppCoordinator.activeCoordinator?.routeToLoginAfterLogout()
    }
}
