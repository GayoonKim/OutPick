//
//  SideMenuViewController.swift
//  OutPick
//
//  Created by 김가윤 on 11/25/24.
//

import UIKit

class SideMenuViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.layer.cornerRadius = 20
        self.view.clipsToBounds = true
        
        self.view.backgroundColor = .init(white: 0.3, alpha: 0.3)
    }
}
