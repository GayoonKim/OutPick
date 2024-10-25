//
//  ChatViewController.swift
//  OutPick
//
//  Created by 김가윤 on 10/14/24.
//

import UIKit

class ChatViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let backButton = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: self, action: #selector(backButtonTapped))
        backButton.tintColor = .black
        self.navigationItem.leftBarButtonItem = backButton
    }
    
    @objc func backButtonTapped() {
//        self.navigationController?.popViewController(animated: true)
        
        let chatListVC = self.storyboard?.instantiateViewController(identifier: "ChatList") as? UINavigationController
        self.view.window?.rootViewController = chatListVC
        self.view.window?.makeKeyAndVisible()
    }

}
