//
//  ChatEditViewController.swift
//  OutPick
//
//  Created by 김가윤 on 6/14/25.
//

import UIKit

class ChatEditViewController: UIViewController {
    private lazy var customNavigationBar: CustomNavigationBarView = {
        let navBar = CustomNavigationBarView()
        navBar.translatesAutoresizingMaskIntoConstraints = false
        
        return navBar
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.backgroundColor = .white
        
        setupCustomNavigationBar()
    }
}


private extension ChatEditViewController {
    @MainActor
    func setupCustomNavigationBar() {
        self.view.addSubview(customNavigationBar)
        
        NSLayoutConstraint.activate([
            customNavigationBar.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            customNavigationBar.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            customNavigationBar.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
        ])
        
        customNavigationBar.configure(leftViews: [UIButton.navButtonIcon("xmark", action: backBtnTapped)],
                                      centerViews: [UILabel.navTitle("오픈채팅 관리")],
                                      rightViews: [])
    }
    
    private func backBtnTapped() {
        self.dismiss(animated: true)
    }
}
