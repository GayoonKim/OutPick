//
//  MyMenuViewController.swift
//  OutPick
//
//  Created by 김가윤 on 12/16/24.
//

import UIKit
import KakaoSDKUser
import KakaoSDKCommon
import FirebaseAuth
import GoogleSignIn

class MyPageViewController: UIViewController {
    
    // 한국어 주석: 로그아웃 과정에서 여러 콜백이 동시에 돌아도 로그인 화면 전환은 1번만 수행
    private var didRouteToLogin = false

    private lazy var customNavigationBar: CustomNavigationBarView = {
        let customNavigationBar = CustomNavigationBarView()
        customNavigationBar.translatesAutoresizingMaskIntoConstraints = false
        return customNavigationBar
    }()
    
    // MARK: - MyPage Body Views
    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.alwaysBounceVertical = true
        sv.showsVerticalScrollIndicator = true
        return sv
    }()

    private let contentView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    
    private let heroBackgroundView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = OutPickTheme.ColorToken.surfaceBase
        return v
    }()

    private let heroTitleLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.text = "OutPick"
        l.font = .systemFont(ofSize: 36, weight: .black)
        l.textAlignment = .center
        l.textColor = OutPickTheme.ColorToken.accent
        return l
    }()

    private let profileImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 60 // size 120의 반
        iv.layer.borderWidth = 1
        iv.layer.borderColor = OutPickTheme.ColorToken.borderSubtle.cgColor
        iv.backgroundColor = OutPickTheme.ColorToken.surfaceBase
        iv.image = UIImage(systemName: "person.crop.circle")
        iv.tintColor = OutPickTheme.ColorToken.textTertiary
        return iv
    }()

    private lazy var editProfileButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "프로필 수정"
        config.baseBackgroundColor = OutPickTheme.ColorToken.accent
        config.baseForegroundColor = OutPickTheme.ColorToken.backgroundBase
        let b = UIButton(configuration: config)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.addTarget(self, action: #selector(didTapEditProfile), for: .touchUpInside)
        return b
    }()

    private let nicknameLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 20, weight: .semibold)
        l.textColor = OutPickTheme.ColorToken.textPrimary
        l.textAlignment = .center
        l.text = "닉네임"
        return l
    }()

    private let genderLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 14, weight: .regular)
        l.textColor = OutPickTheme.ColorToken.textSecondary
        l.textAlignment = .center
        l.text = "성별"
        return l
    }()

    private let bioContainerView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = OutPickTheme.ColorToken.surfaceBase
        v.layer.cornerRadius = 12
        v.layer.borderWidth = 1
        v.layer.borderColor = OutPickTheme.ColorToken.borderSubtle.cgColor
        v.layer.masksToBounds = true
        return v
    }()

    private let bioLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.numberOfLines = 0
        l.font = .systemFont(ofSize: 15)
        l.textColor = OutPickTheme.ColorToken.textPrimary
        l.text = "자기소개가 여기에 표시됩니다."
        return l
    }()
    
    private let infoSeparatorView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = OutPickTheme.ColorToken.borderSubtle
        return v
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupNavigationBar()
        setupMyPageBody()
        
        guard let profile = LoginManager.shared.currentUserProfile else { return }
        nicknameLabel.text = profile.nickname
        genderLabel.text = profile.gender?.description
    }
    
    @MainActor
    private func setupNavigationBar() {
        self.view.addSubview(customNavigationBar)
        customNavigationBar.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            customNavigationBar.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            customNavigationBar.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            customNavigationBar.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
        ])
        
        customNavigationBar.configureForMyPage(target: self, onSetting: #selector(settingButtonTapped))
    }
    
    @objc private func settingButtonTapped() {
        // 1) 찾기: 이 뷰 컨트롤러의 액션(#selector(settingButtonTapped))을 갖는 버튼을 커스텀 네비게이션 바 내부에서 탐색
        guard let settingsButton = findSettingsButtonInCustomNav() else {
            // 못 찾으면 그냥 로그아웃만 바로 수행하거나, 필요한 경우 얼럿으로 대체 가능
            // logOutBtnTapped(UIButton(type: .system))
            return
        }

        // 2) 메뉴 정의: 로그아웃 (destructive)
        let logoutAction = UIAction(title: "로그아웃",
                                    image: UIImage(systemName: "rectangle.portrait.and.arrow.right"),
                                    attributes: .destructive) { [weak self] _ in
            guard let self = self else { return }
            // 기존 구현 재사용
            self.logOutBtnTapped(settingsButton)
        }
        let menu = UIMenu(title: "", children: [logoutAction])

        // 3) 버튼에 메뉴 장착 + 탭 시 바로 메뉴가 뜨도록 설정
        settingsButton.menu = menu
        settingsButton.showsMenuAsPrimaryAction = true

        // 4) 이번 탭에서도 즉시 메뉴가 보이도록 트리거
        if #available(iOS 15.0, *) {
            settingsButton.sendActions(for: .primaryActionTriggered)
        } else {
            settingsButton.sendActions(for: .touchUpInside)
        }
    }
    
    @MainActor
    private func goToLoginScreen() {
        if let coordinator = AppCoordinator.activeCoordinator {
            coordinator.routeToLoginAfterLogout()
            return
        }

        // CompositionRoot로 로그인 화면을 생성 (LoginViewController는 viewModel 주입 필요)
        let loginViewController = LoginCompositionRoot.makeLoginViewController(
            onLoginSuccess: { authenticatedUser in
                Task { @MainActor in
                    if let coordinator = AppCoordinator.activeCoordinator {
                        coordinator.handleLoginSuccess(authenticatedUser)
                    } else {
                        LoginManager.shared.setAuthenticatedUser(authenticatedUser)
                    }
                }
            }
        )

        let nav = UINavigationController(rootViewController: loginViewController)
        nav.isNavigationBarHidden = true

        // 한국어 주석: 기존 화면들이 남아있지 않도록 root 교체
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first
        else { return }

        window.rootViewController = nav
        window.makeKeyAndVisible()
    }

    private func routeToLoginOnce() {
        // 구글/카카오 콜백이 각각 호출돼도 1회만 이동
        guard !didRouteToLogin else { return }
        didRouteToLogin = true
        Task { @MainActor in
            self.goToLoginScreen()
        }
    }
    
    private func logOutBtnTapped(_ sender: UIButton) {
        let currentProfileCacheAccount = LoginManager.shared.getUserDocumentID.isEmpty
            ? "UserProfile"
            : "UserProfile:\(LoginManager.shared.getUserDocumentID)"
        KeychainManager.shared.delete(service: "GayoonKim.OutPick", account: currentProfileCacheAccount)
        KeychainManager.shared.delete(service: "GayoonKim.OutPick", account: "UserProfile")
        KeychainManager.shared.delete(service: "GayoonKim.OutPick", account: "AuthenticatedUser")
        LoginManager.shared.setUserEmail("")
        LoginManager.shared.setCurrentUserProfile(nil)
        LoginManager.shared.clearAuthUserKey()
        LoginManager.shared.clearUserDocumentID()
        didRouteToLogin = false

        // 1) Firebase/Google 로그아웃(되어있지 않아도 안전하게 시도)
        do {
            try Auth.auth().signOut()
        } catch {
            print("Firebase signOut error: \(error)")
        }
        GIDSignIn.sharedInstance.signOut()

        // 2) Kakao 로그아웃(토큰이 없어도 에러는 무시)
        if UserApi.isKakaoTalkLoginAvailable() {
            UserApi.shared.logout { error in
                if let error = error {
                    if let sdkError = error as? SdkError,
                       case .ClientFailed(let reason, _) = sdkError,
                       case .TokenNotFound = reason {
                        print("이미 로그아웃 상태 (토큰 없음), 무시")
                    } else {
                        print("Kakao logout error: \(error)")
                    }
                }
                self.routeToLoginOnce()
            }
        } else {
            // 카카오톡 로그인 불가 환경에서도 동일하게 logout 시도
            UserApi.shared.logout { error in
                if let error = error {
                    print("Kakao logout error: \(error)")
                }
                self.routeToLoginOnce()
            }
        }

        // (주의) 카카오 로그아웃은 비동기라 콜백에서 이동 처리. 구글/파이어베이스는 즉시 완료.
    }
    
    // 커스텀 네비게이션 바 내부에서 이 VC의 settingButtonTapped를 타겟으로 가진 버튼을 찾아 반환
    private func findSettingsButtonInCustomNav() -> UIButton? {
        return findButton(in: customNavigationBar, target: self, actionName: "settingButtonTapped")
    }

    // 서브뷰를 재귀적으로 순회하며 특정 타겟/액션을 가진 UIButton을 찾는 유틸리티
    private func findButton(in root: UIView, target: AnyObject, actionName: String) -> UIButton? {
        for sub in root.subviews {
            if let button = sub as? UIButton {
                let actions = button.actions(forTarget: target, forControlEvent: .touchUpInside) ?? []
                if actions.contains(actionName) {
                    return button
                }
            }
            if let found = findButton(in: sub, target: target, actionName: actionName) {
                return found
            }
        }
        return nil
    }
    
    @MainActor
    private func setupMyPageBody() {
        view.backgroundColor = OutPickTheme.ColorToken.backgroundBase
        scrollView.backgroundColor = OutPickTheme.ColorToken.backgroundBase
        contentView.backgroundColor = OutPickTheme.ColorToken.backgroundBase

        // 0) Scroll view + content view
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: customNavigationBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        scrollView.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        // 1) Hero background with centered "OutPick"
        contentView.addSubview(heroBackgroundView)
        heroBackgroundView.addSubview(heroTitleLabel)
        heroBackgroundView.backgroundColor = OutPickTheme.ColorToken.surfaceBase

        NSLayoutConstraint.activate([
            heroBackgroundView.topAnchor.constraint(equalTo: contentView.topAnchor),
            heroBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            heroBackgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            heroBackgroundView.heightAnchor.constraint(equalToConstant: 180),

            heroTitleLabel.centerXAnchor.constraint(equalTo: heroBackgroundView.centerXAnchor),
            heroTitleLabel.centerYAnchor.constraint(equalTo: heroBackgroundView.centerYAnchor)
        ])

        // 2) Profile image overlapping bottom of hero by half (centerY = hero bottom)
        contentView.addSubview(profileImageView)
        NSLayoutConstraint.activate([
            profileImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            profileImageView.centerYAnchor.constraint(equalTo: heroBackgroundView.bottomAnchor),
            profileImageView.widthAnchor.constraint(equalToConstant: 120),
            profileImageView.heightAnchor.constraint(equalToConstant: 120)
        ])

        // 3) Edit profile button
        contentView.addSubview(editProfileButton)
        NSLayoutConstraint.activate([
            editProfileButton.topAnchor.constraint(equalTo: profileImageView.bottomAnchor, constant: 12),
            editProfileButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            editProfileButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10)
        ])

        // 4~5) Profile Info Container (닉네임 + 성별 + 자기소개)
        contentView.addSubview(bioContainerView)
        bioContainerView.addSubview(nicknameLabel)
        bioContainerView.addSubview(genderLabel)
        bioContainerView.addSubview(infoSeparatorView)
        bioContainerView.addSubview(bioLabel)

        NSLayoutConstraint.activate([
            // Container: 프로필 수정 버튼에서 10pt 아래
            bioContainerView.topAnchor.constraint(equalTo: editProfileButton.bottomAnchor, constant: 10),
            bioContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            bioContainerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            bioContainerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            bioContainerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 88),

            // 닉네임: 컨테이너 leading 10
            nicknameLabel.topAnchor.constraint(equalTo: bioContainerView.topAnchor, constant: 12),
            nicknameLabel.leadingAnchor.constraint(equalTo: bioContainerView.leadingAnchor, constant: 10),

            // 성별: 닉네임의 centerX 유지
            genderLabel.topAnchor.constraint(equalTo: nicknameLabel.bottomAnchor, constant: 4),
            genderLabel.centerXAnchor.constraint(equalTo: nicknameLabel.centerXAnchor),

            // 구분선: 성별 아래 12, 좌우 12, 헤어라인 높이
            infoSeparatorView.topAnchor.constraint(equalTo: genderLabel.bottomAnchor, constant: 12),
            infoSeparatorView.leadingAnchor.constraint(equalTo: bioContainerView.leadingAnchor, constant: 12),
            infoSeparatorView.trailingAnchor.constraint(equalTo: bioContainerView.trailingAnchor, constant: -12),
            infoSeparatorView.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),

            // 자기소개 라벨: 좌우 12, 구분선 아래 12, 컨테이너 하단과 12
            bioLabel.topAnchor.constraint(equalTo: infoSeparatorView.bottomAnchor, constant: 12),
            bioLabel.leadingAnchor.constraint(equalTo: bioContainerView.leadingAnchor, constant: 12),
            bioLabel.trailingAnchor.constraint(equalTo: bioContainerView.trailingAnchor, constant: -12),
            bioLabel.bottomAnchor.constraint(equalTo: bioContainerView.bottomAnchor, constant: -12)
        ])
    }

    @objc private func didTapEditProfile() {
        // TODO: 프로필 수정 화면으로 이동하거나 편집 액션 연결
        print("✏️ 프로필 수정 버튼 탭")
    }

    // 선택적으로, 외부 데이터 주입 시 사용
    func updateProfile(nickname: String?, gender: String?, bio: String?, image: UIImage?) {
        if let nickname = nickname { nicknameLabel.text = nickname }
        if let gender = gender { genderLabel.text = gender }
        if let bio = bio { bioLabel.text = bio }
        if let image = image { profileImageView.image = image }
    }
}
