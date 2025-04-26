//
//  MainTabBarController.swift
//  OutPick
//
//  Created by 김가윤 on 2/19/25.
//

import UIKit

class MainTabBarController: UITabBarController {

    private lazy var tab_bar_view: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 30
        view.backgroundColor = .quaternarySystemFill
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = false
        return view
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        set_view()
    }

    private func set_view() {
        self.tabBar.isTranslucent = false
        self.tabBar.backgroundColor = .clear
//        view.addSubview(tab_bar_view)
//        NSLayoutConstraint.activate([
//            tab_bar_view.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -33),
//            tab_bar_view.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -20),
//            tab_bar_view.heightAnchor.constraint(equalToConstant: 60),
//            tab_bar_view.centerXAnchor.constraint(equalTo: view.centerXAnchor)
//        ])
    }

}
