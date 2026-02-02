//
//  CustomTabBarViewController.swift
//  OutPick
//
//  Created by 김가윤 on 5/30/25.
//

import UIKit
import Combine
import SwiftUI

class CustomTabBarViewController: UIViewController {

    private let customTabBar = CustomTabBarView()
    private var currentChildViewController: UIViewController?
    private var currentTabIndex: Int?
    private var tabViewControllers: [Int: UIViewController] = [:]
    private var cancellables = Set<AnyCancellable>()

    /// 앱 전역 의존성 컨테이너 (SceneDelegate 등에서 주입해야 합니다)
    var container: AppContainer? {
        didSet {
            // 컨테이너가 바뀌면 탭 캐시를 전부 무효화하여(로그아웃/재로그인 등) 의존성 갱신을 확실히 반영
            guard oldValue !== container else { return }
            invalidateAllTabCaches(reloadVisibleTab: true)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        print("CustomTabBar instance:", ObjectIdentifier(self))
        // ✅ container 주입 강제(디버그에서 즉시 확인)
        assert(container != nil, "CustomTabBarViewController.container가 주입되지 않았습니다. SceneDelegate에서 주입 후 표시해주세요.")

        self.view.backgroundColor = .white
        setupCustomTabBar()
    }

    func viewController(_ index: Int) -> UIViewController {
        switch index {
        case 0:
            // 메인 탭: 오픈채팅 목록
            let listVC = RoomListsCollectionViewController(collectionViewLayout: UICollectionViewFlowLayout())
            let nav = UINavigationController(rootViewController: listVC)
            nav.isNavigationBarHidden = true
            return nav

        case 1:
            // 참여중인 오픈채팅 목록
            let joinedListVC = JoinedRoomsViewController()
            let nav = UINavigationController(rootViewController: joinedListVC)
            nav.isNavigationBarHidden = true
            return nav

        case 2:
            // 룩북 탭 (SwiftUI)
            guard let container else {
                assertionFailure("Lookbook 탭 생성 시점에 container가 nil 입니다. 주입 흐름을 확인해주세요.")
                return UINavigationController(rootViewController: UIViewController())
            }

            let lookbookView =
                LookbookHomeView(
                    viewModel: container.lookbookHomeViewModel,
                    provider: container.provider
                )
                    .environment(\.repositoryProvider, container.provider) // ✅ Environment로도 공급

            let hostingVC = UIHostingController(rootView: lookbookView)
            let nav = UINavigationController(rootViewController: hostingVC)
            nav.isNavigationBarHidden = true
            return nav

        case 3:
            // 내 설정 탭
            let myPageVC = MyPageViewController()
            let nav = UINavigationController(rootViewController: myPageVC)
            nav.isNavigationBarHidden = true
            return nav

        default:
            return UINavigationController(rootViewController: UIViewController())
        }
    }

    @MainActor
    private func setupCustomTabBar() {
        view.addSubview(customTabBar)
        customTabBar.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            customTabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            customTabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            customTabBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            customTabBar.heightAnchor.constraint(equalToConstant: 60),
        ])

        customTabBar.updateButtonStates(0)
        switchScreen(0)

        customTabBar.tabSelected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] index in
                guard let self = self else { return }
                self.switchScreen(index)
            }
            .store(in: &cancellables)
    }

    func switchScreen(_ index: Int) {
        if currentTabIndex == index { return }

        if let current = currentChildViewController {
            current.willMove(toParent: nil)
            current.view.removeFromSuperview()
            current.removeFromParent()
        }

        let vc: UIViewController
        if let cached = tabViewControllers[index] {
            vc = cached
        } else {
            vc = viewController(index)
            tabViewControllers[index] = vc
        }

        addChild(vc)
        view.insertSubview(vc.view, belowSubview: customTabBar)
        vc.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            vc.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            vc.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            vc.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            vc.view.bottomAnchor.constraint(equalTo: customTabBar.topAnchor)
        ])
        vc.didMove(toParent: self)

        customTabBar.updateButtonStates(index)

        currentChildViewController = vc
        currentTabIndex = index
    }

    /// 모든 탭의 캐시를 무효화합니다.
    /// - Parameters:
    ///   - reloadVisibleTab: 현재 보고 있는 탭을 즉시 재생성하여 교체할지 여부
    private func invalidateAllTabCaches(reloadVisibleTab: Bool) {
        tabViewControllers.removeAll()

        // 현재 화면을 보고 있다면, 같은 탭 인덱스로 즉시 다시 생성해서 교체
        if reloadVisibleTab {
            let targetIndex = currentTabIndex ?? 0
            // switchScreen은 같은 인덱스면 early-return 하므로, 강제로 다시 전환되게 만듭니다.
            currentTabIndex = nil
            switchScreen(targetIndex)
        }
    }

    /// 특정 탭의 캐시를 무효화합니다.
    /// - Parameters:
    ///   - index: 탭 인덱스
    ///   - reloadIfVisible: 현재 화면이 해당 탭이면 즉시 다시 생성하여 교체할지 여부
    private func invalidateTabCache(index: Int, reloadIfVisible: Bool) {
        tabViewControllers[index] = nil

        // 현재 보고 있는 탭이면 즉시 재생성하여 교체
        if reloadIfVisible, currentTabIndex == index {
            // switchScreen은 같은 인덱스면 early-return 하므로, 강제로 다시 전환되게 만듭니다.
            currentTabIndex = nil
            switchScreen(index)
        }
    }

    /// 외부(로그아웃/재로그인 등)에서 탭 캐시를 전부 새로 만들고 싶을 때 호출
    func invalidateAllTabsCache(reloadVisibleTab: Bool = true) {
        invalidateAllTabCaches(reloadVisibleTab: reloadVisibleTab)
    }

    /// 외부에서 Lookbook 탭(2)만 강제로 새로 만들고 싶을 때 호출
    func invalidateLookbookTabCache(reloadIfVisible: Bool = true) {
        invalidateTabCache(index: 2, reloadIfVisible: reloadIfVisible)
    }
}
