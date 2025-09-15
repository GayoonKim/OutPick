//
//  CustomTabBarViewController.swift
//  OutPick
//
//  Created by 김가윤 on 5/30/25.
//

import UIKit
import Combine

class CustomTabBarViewController: UICollectionViewController {

    private let customTabBar = CustomTabBarView()
    private var currentChildViewController: UIViewController?
    private var currentTabIndex: Int?
    private var tabViewControllers: [Int: UIViewController] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCustomTabBar()
    }
    
    func viewController(_ index: Int) -> UIViewController {
        fatalError("Subclass must override viewController(for:)")
    }
    
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
        
        customTabBar.tabSelected
            .receive(on: RunLoop.main)
            .sink{ [weak self] index in
                guard let self = self else { return }
                self.switchScreen(index)
                self.customTabBar.updateButtonStates(index)
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
        vc.view.frame = view.bounds
        vc.didMove(toParent: self)
        
        customTabBar.updateButtonStates(index)
        
        currentChildViewController = vc
        currentTabIndex = index
        
    }
}
