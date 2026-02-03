//
//  CustomTabBarViewController.swift
//  OutPick
//
//  Created by 김가윤 on 5/30/25.
//

import UIKit
import Combine

final class CustomTabBarViewController: UIViewController {

    private let customTabBar = CustomTabBarView()
    private var currentChildViewController: UIViewController?
    private var currentTabIndex: Int?
    private var tabViewControllers: [Int: UIViewController] = [:]
    private var cancellables = Set<AnyCancellable>()

    /// 탭 화면 생성 책임을 외부(CompositionRoot/Coordinator)로 위임하기 위한 빌더
    /// - Note: 빌더가 바뀌면(로그아웃/재로그인, 의존성 교체 등) 캐시를 무효화합니다.
    var tabBuilder: (any MainTabBuilding)? {
        didSet {
            // 빌더가 바뀌면 각 탭의 조립 방식이 바뀔 수 있으므로 캐시 무효화
            invalidateAllTabCaches(reloadVisibleTab: true)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        if tabBuilder == nil {
            assertionFailure("CustomTabBarViewController.tabBuilder가 nil 입니다. AppCoordinator/CompositionRoot에서 주입해주세요.")
        }

        setupCustomTabBar()
    }

    func viewController(_ index: Int) -> UIViewController {
        guard let tabBuilder else {
            assertionFailure("CustomTabBarViewController.tabBuilder가 nil 입니다. AppCoordinator/CompositionRoot에서 주입해주세요.")
            return UINavigationController(rootViewController: UIViewController())
        }
        return tabBuilder.makeViewController(for: index)
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

        // 기본 탭 선택(0)
        customTabBar.updateButtonStates(0)
        switchScreen(0)

        // 탭 선택 이벤트 구독
        customTabBar.tabSelected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] index in
                guard let self else { return }
                self.switchScreen(index)
            }
            .store(in: &cancellables)
    }

    func switchScreen(_ index: Int) {
        // 같은 탭 재선택이면 아무 것도 하지 않음
        if currentTabIndex == index { return }

        // 기존 child 제거
        if let current = currentChildViewController {
            current.willMove(toParent: nil)
            current.view.removeFromSuperview()
            current.removeFromParent()
        }

        // 캐시가 있으면 재사용, 없으면 생성 후 캐시
        let vc: UIViewController
        if let cached = tabViewControllers[index] {
            vc = cached
        } else {
            vc = viewController(index)
            tabViewControllers[index] = vc
        }

        // 새 child 추가
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

        if reloadVisibleTab {
            let targetIndex = currentTabIndex ?? 0
            // 한국어 주석: switchScreen이 같은 인덱스면 early-return 하므로 강제로 다시 전환되게 함
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

        if reloadIfVisible, currentTabIndex == index {
            // switchScreen이 같은 인덱스면 early-return 하므로 강제로 다시 전환되게 함
            currentTabIndex = nil
            switchScreen(index)
        }
    }

    // MARK: - Public API (외부에서 캐시 제어)

    func invalidateAllTabsCache(reloadVisibleTab: Bool = true) {
        invalidateAllTabCaches(reloadVisibleTab: reloadVisibleTab)
    }
}
