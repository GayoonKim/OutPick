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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCustomTabBar()
        self.view.backgroundColor = .white
    }

    func viewController(_ index: Int) -> UIViewController {
        switch index {
        case 0:
            // Weather tab
            let weatherVC = HomeCollectionViewController(collectionViewLayout: UICollectionViewFlowLayout())
            let nav = UINavigationController(rootViewController: weatherVC)
            nav.isNavigationBarHidden = true
            return nav
        case 1:
            // Chat list tab
            let listVC = RoomListsCollectionViewController(collectionViewLayout: UICollectionViewFlowLayout())
            let nav = UINavigationController(rootViewController: listVC)
            nav.isNavigationBarHidden = true
            return nav
        case 2:
            let joinedListVC = JoinedRoomsViewController()
            let nav = UINavigationController(rootViewController: joinedListVC)
            nav.isNavigationBarHidden = true
            return nav
        case 3:
            // Lookbook tab (SwiftUI)
            let lookbookView = LookbookHomeView() // SwiftUI 화면
            let hostingVC = UIHostingController(rootView: lookbookView)
            let nav = UINavigationController(rootViewController: hostingVC)
            nav.isNavigationBarHidden = true
            return nav
        case 4:
            // Settings tab
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
            .sink{ [weak self] index in
                guard let self = self else { return }
                self.switchScreen(index)
//                self.customTabBar.updateButtonStates(index)
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
//        vc.view.frame = view.bounds
        vc.didMove(toParent: self)
        
        customTabBar.updateButtonStates(index)
        
        currentChildViewController = vc
        currentTabIndex = index
        
    }
}
