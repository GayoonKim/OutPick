//
//  ActivityIndicator.swift
//  OutPick
//
//  Created by 김가윤 on 2/18/25.
//

import Foundation
import UIKit

class LoadingIndicator {
    
    static let shared = LoadingIndicator()
    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.color = .black
        return indicator
    }()
    
    private init() {}
    
    func start(on viewController: UIViewController) {
        DispatchQueue.main.async {
            if self.activityIndicator.superview == nil {
                self.activityIndicator.center = viewController.view.center
                viewController.view.addSubview(self.activityIndicator)
            }
            viewController.view.bringSubviewToFront(self.activityIndicator)
            self.activityIndicator.startAnimating()
            
        }
    }
    
    func stop() {
        DispatchQueue.main.async {
            
            self.activityIndicator.stopAnimating()
            self.activityIndicator.removeFromSuperview()
            
        }
    }
    
    var isLoading: Bool {
        return self.activityIndicator.isAnimating
    }
    
}
