//
//  ChatModalPushTransitionDirection.swift
//  OutPick
//
//  Created by 김가윤 on 6/12/25.
//

import UIKit

protocol ChatModalPushAnimatable {}

enum ChatModalPushTransitionDirection {
    case leftToRight
    case rightToLeft
}

final class ChatModalPushTransitionManager {
    static func present(_ viewController: UIViewController, from presentingVC: UIViewController, direction: ChatModalPushTransitionDirection = .rightToLeft, duration: TimeInterval = 0.35) {
        if viewController is ChatModalPushAnimatable {
            let transition = CATransition()
            transition.duration = duration
            transition.type = .push
            transition.subtype = direction == .rightToLeft ? .fromRight : .fromLeft
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            presentingVC.view.window?.layer.add(transition, forKey: kCATransition)
        }
        
        presentingVC.present(viewController, animated: false)
    }
    
    static func dismiss(from presentingVC: UIViewController, direction: ChatModalPushTransitionDirection = .leftToRight, duration: CFTimeInterval = 0.35) {
        if presentingVC is ChatModalPushAnimatable {
            let transition = CATransition()
            transition.duration = duration
            transition.type = .push
            transition.subtype = direction == .leftToRight ? .fromLeft : .fromRight
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            presentingVC.view.window?.layer.add(transition, forKey: kCATransition)
        }
        
        presentingVC.dismiss(animated: false)
    }
}
