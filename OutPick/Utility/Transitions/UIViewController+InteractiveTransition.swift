//
//  UIViewController + InteractiveTransition.swift
//  OutPick
//
//  Created by 김가윤 on 6/13/25.
//

import UIKit
import ObjectiveC

private var interactionControllerKey: UInt8 = 0

extension UIViewController: UIViewControllerTransitioningDelegate {
    private var interactiveTransition: UIPercentDrivenInteractiveTransition? {
        get { objc_getAssociatedObject(self, &interactionControllerKey) as? UIPercentDrivenInteractiveTransition }
        set { objc_setAssociatedObject(self, &interactionControllerKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    public func attachInteractiveDismissGesture() {
        self.modalPresentationStyle = .custom
        self.transitioningDelegate = self
        
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleInteractiveDismiss(_:)))
        self.view.addGestureRecognizer(panGesture)
    }

    @objc private func handleInteractiveDismiss(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        let progress = max(0, min(1, translation.x / view.bounds.width))
        
        switch gesture.state {
        case .began:
            if translation.x > 0 {
                interactiveTransition = UIPercentDrivenInteractiveTransition()
                self.dismiss(animated: true)
            }
            
        case .changed:
            interactiveTransition?.update(progress)
            
        case .ended, .cancelled:
            if progress > 0.5 {
                interactiveTransition?.finish()
            } else {
                interactiveTransition?.cancel()
            }
            interactiveTransition = nil
            default : break
        }
    }
    
    public func animationController(forDismissed dismissed: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        return PopAnimator()
    }

    public func interactionControllerForDismissal(using animator: any UIViewControllerAnimatedTransitioning) -> (any UIViewControllerInteractiveTransitioning)? {
        return interactiveTransition
    }
}
