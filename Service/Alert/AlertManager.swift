//
//  AlertManager.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import UIKit

class AlertManager {
    
    static let shared = AlertManager()
    
    @MainActor
    static func showAlertNoHandler(title: String, message: String, viewController: UIViewController) {
        
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default, handler: nil))
        viewController.present(alert, animated: true, completion: nil)
        
    }
    
    @MainActor
    static func showDuplicateLoginAlert(onConfirm: @escaping () -> Void) {
        guard let top = topViewController() else {
            onConfirm()
            return
        }

        let alert = UIAlertController(
            title: "중복 로그인",
            message: "다른 기기에서 로그인이 감지되어 현재 기기에서는 로그아웃 처리됩니다.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "확인", style: .default) { _ in
            onConfirm()
        })

        // 이미 다른 alert가 떠있어도 중복 present로 크래시가 나지 않도록 방어
        if top.presentedViewController == nil {
            top.present(alert, animated: true)
        } else {
            top.dismiss(animated: false) {
                top.present(alert, animated: true)
            }
        }
    }

    private static func topViewController(base: UIViewController? = {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let keyWindow = scenes
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        return keyWindow?.rootViewController
    }()) -> UIViewController? {

        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
}
