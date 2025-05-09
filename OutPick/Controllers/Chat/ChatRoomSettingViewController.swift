//
//  ChatRoomSettingViewController.swift
//  OutPick
//
//  Created by 김가윤 on 8/5/24.
//

import UIKit

class ChatRoomSettingViewController: UIViewController, UIGestureRecognizerDelegate, UINavigationControllerDelegate {

    var interactiveTransition: UIPercentDrivenInteractiveTransition?

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = .white

        // Back button (no CATransition)
        let backButton = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: self, action: #selector(backButtonTapped))
        backButton.tintColor = .black
        self.navigationItem.leftBarButtonItem = backButton
        
        self.navigationController?.attachPopGesture(to: self.view)
    }

    @objc private func backButtonTapped() {
        self.navigationController?.popViewController(animated: true)
    }
}
