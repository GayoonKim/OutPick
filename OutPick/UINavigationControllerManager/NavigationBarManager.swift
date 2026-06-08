//
//  NavigationBarBackButton.swift
//  OutPick
//
//  Created by 김가윤 on 1/14/25.
//

import UIKit

class NavigationBarManager {
    
    static func configureBackButton(for viewController: UIViewController) {
        
        let backButton = UIBarButtonItem()
        backButton.tintColor = OutPickTheme.ColorToken.accent
        viewController.navigationController?.navigationBar.topItem?.backBarButtonItem = backButton
        
    }
    
}
