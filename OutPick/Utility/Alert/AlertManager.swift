//
//  AlertManager.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import UIKit

class AlertManager {
    
    static let shared = AlertManager()
    
    static func showAlert(title: String, message: String, viewController: UIViewController) {
        DispatchQueue.main.async {
            
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "확인", style: .default, handler: nil))
            viewController.present(alert, animated: true, completion: nil)
            
        }
    }
    
}
