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
    private var indicator: UIActivityIndicatorView?
    
    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.color = .black
        return indicator
    }()
    
    private init() {}
    
    func start(on viewController: UIViewController) {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.accessibilityIdentifier = "LoadingIndicator" // ✅ 여기서 지정
        indicator.center = viewController.view.center
        indicator.startAnimating()
        viewController.view.addSubview(indicator)
        self.indicator = indicator
        
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
            self.indicator?.stopAnimating()
            self.indicator?.removeFromSuperview()
            self.indicator = nil
            
            self.activityIndicator.stopAnimating()
            self.activityIndicator.removeFromSuperview()
            
        }
    }
    
    var isLoading: Bool {
        return self.activityIndicator.isAnimating
    }
    
}
