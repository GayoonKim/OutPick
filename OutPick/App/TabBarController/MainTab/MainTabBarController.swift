//
//  MainTabBarController.swift
//  OutPick
//
//  Created by Codex on 6/30/26.
//

import UIKit

@MainActor
final class MainTabBarController: UITabBarController {
    private enum Constants {
        static let selectedColor = OutPickTheme.ColorToken.accent
        static let normalColor = OutPickTheme.ColorToken.iconSecondary
        static let backgroundColor = OutPickTheme.ColorToken.surfaceBase
        static let tabBarContentHeight: CGFloat = 54
    }

    var tabBuilder: (any MainTabBuilding)?

    var activeContentViewController: UIViewController? {
        resolvedPresenter(from: selectedViewController)
    }

    var selectedNavigationController: UINavigationController? {
        if let nav = selectedViewController as? UINavigationController {
            return nav
        }
        return selectedViewController?.navigationController
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        view.accessibilityIdentifier = "app.main.root"
        view.backgroundColor = OutPickTheme.ColorToken.backgroundBase
        configureTabBarAppearance()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateTabBarFrameIfNeeded()
    }

    func configure(viewControllers: [UIViewController]) {
        setViewControllers(viewControllers, animated: false)
        selectedIndex = 0
    }

    func selectTab(_ index: Int) {
        guard let controllers = viewControllers,
              controllers.indices.contains(index),
              selectedIndex != index else {
            return
        }
        selectedIndex = index
    }

    func dismissPresentedControllerIfNeeded(animated: Bool) async {
        guard presentedViewController != nil else { return }
        await withCheckedContinuation { continuation in
            dismiss(animated: animated) {
                continuation.resume()
            }
        }
    }

    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = Constants.backgroundColor
        appearance.shadowColor = .clear

        configureItemAppearance(appearance.stackedLayoutAppearance)
        configureItemAppearance(appearance.inlineLayoutAppearance)
        configureItemAppearance(appearance.compactInlineLayoutAppearance)

        tabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            tabBar.scrollEdgeAppearance = appearance
        }
        tabBar.tintColor = Constants.selectedColor
        tabBar.unselectedItemTintColor = Constants.normalColor
        tabBar.isTranslucent = false
    }

    private func updateTabBarFrameIfNeeded() {
        let fittingHeight = Constants.tabBarContentHeight + (view.window?.safeAreaInsets.bottom ?? 0)
        var frame = tabBar.frame
        let targetY = view.bounds.height - fittingHeight

        guard abs(frame.height - fittingHeight) > 0.5 || abs(frame.origin.y - targetY) > 0.5 else {
            return
        }

        frame.size.height = fittingHeight
        frame.origin.y = targetY
        tabBar.frame = frame
    }

    private func configureItemAppearance(_ itemAppearance: UITabBarItemAppearance) {
        itemAppearance.normal.iconColor = Constants.normalColor
        itemAppearance.normal.titleTextAttributes = [
            .foregroundColor: Constants.normalColor,
            .font: UIFont.systemFont(ofSize: 9, weight: .medium)
        ]
        itemAppearance.normal.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: -1)
        itemAppearance.selected.iconColor = Constants.selectedColor
        itemAppearance.selected.titleTextAttributes = [
            .foregroundColor: Constants.selectedColor,
            .font: UIFont.systemFont(ofSize: 9, weight: .medium)
        ]
        itemAppearance.selected.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: -1)
    }

    private func resolvedPresenter(from root: UIViewController?) -> UIViewController? {
        guard var current = root else { return nil }

        if let nav = current as? UINavigationController {
            current = nav.visibleViewController ?? nav
        } else if let tab = current as? UITabBarController {
            current = tab.selectedViewController ?? tab
        }

        while let presented = current.presentedViewController {
            current = presented
        }

        if let nav = current as? UINavigationController {
            return nav.visibleViewController ?? nav
        }

        return current
    }
}

extension MainTabBarController: UITabBarControllerDelegate {
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        selectedViewController !== viewController
    }
}
