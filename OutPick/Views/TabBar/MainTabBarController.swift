//
//  MainTabBarController.swift
//  OutPick
//
//  Created by 김가윤 on 12/17/24.
//

import UIKit

class MainTabBarController: UITabBarController {

    var backgroundView: UIView!
    let spacing: CGFloat = 12
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
//        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
//            self.addTabBarIndicatorView(index: 0, isFirstTime: true)
//        }
        
        
    }
    
//    private func addTabBarIndicatorView(index: Int, isFirstTime: Bool = false) {
//        guard let tabView = tabBar.items?[index].value(forKey: "view") as? UIView else { return }
//        
//        if !isFirstTime {
//            backgroundView.removeFromSuperview()
//        }
//        
//        backgroundView = UIView(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
//        backgroundView.backgroundColor = UIColor(white: 0.1, alpha: 0.05)
//        backgroundView.layer.cornerRadius = backgroundView.frame.width / 2
//        backgroundView.clipsToBounds = true
//        backgroundView.center = CGPoint(x: tabView.center.x, y: tabView.center.y)
//        
//        tabView.insertSubview(backgroundView, at: index)
//    }
    
    override func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        
    }
}

//extension MainTabBarController: UITabBarControllerDelegate {
//    override func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
//        DispatchQueue.main.async {
//            self.addTabBarIndicatorView(index: self.selectedIndex)
//        }
//    }
//    
//    
//}
