//
//  MainTabBarController.swift
//  OutPick
//
//  Created by 김가윤 on 2/19/25.
//

import UIKit

class MainTabBarController: UITabBarController, UITabBarControllerDelegate {
    
    private let customTabBar = UIView()
    private let buttons: [UIButton] = ["cloud.sun.fill", "bubble.left.and.bubble.right.fill", "bubble.middle.bottom.fill", "magnifyingglass", "gearshape.fill"].map {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: $0), for: .normal)
        button.tintColor = .gray
        
        return button
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }

    func hideCustomTabBar() {
        customTabBar.isHidden = true
    }
    
    func showCustomTabBar(animated: Bool = true) {
        customTabBar.isHidden = false
    }
    
    private func setupCustomTabBar() {
        view.addSubview(customTabBar)
        customTabBar.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            customTabBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            customTabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            customTabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            customTabBar.heightAnchor.constraint(equalToConstant: 80)
        ])

        let stack = UIStackView(arrangedSubviews: buttons)
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        
        customTabBar.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: customTabBar.centerXAnchor),
            stack.topAnchor.constraint(equalTo: customTabBar.topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: customTabBar.leadingAnchor, constant: 15),
            stack.trailingAnchor.constraint(equalTo: customTabBar.trailingAnchor, constant: -15)
        ])
        
        for (index, button) in buttons.enumerated() {
            button.tag = index
            button.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
        }
    }
    
    @objc private func tabTapped(_ sender: UIButton) {
        selectedIndex = sender.tag
        updateTabColors()
    }
    
    private func updateTabColors() {
        for (index, button) in buttons.enumerated() {
            button.tintColor = (index == selectedIndex) ? .black : .gray
        }
    }
}
