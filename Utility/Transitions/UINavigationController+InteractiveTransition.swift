//
//  UINavigationController+InteractiveTransition.swift
//  OutPick
//
//  Created by 김가윤 on 5/9/25.
//

import UIKit

private var interactiveTransitionKey: UInt8 = 0

extension UINavigationController: @retroactive UINavigationControllerDelegate {
    private var interactiveTransition: UIPercentDrivenInteractiveTransition? {
        get { objc_getAssociatedObject(self, &interactiveTransitionKey) as? UIPercentDrivenInteractiveTransition }
        set { objc_setAssociatedObject(self, &interactiveTransitionKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    public func attachPushGesture(to view: UIView, viewControllerProvider: @escaping () -> UIViewController) {
        self.delegate = self
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePushPan(_:)))
        panGesture.name = "push"
        objc_setAssociatedObject(panGesture, "viewControllerProvider", viewControllerProvider, .OBJC_ASSOCIATION_COPY_NONATOMIC)
        view.addGestureRecognizer(panGesture)
    }

    public func attachPopGesture(to view: UIView) {
        self.delegate = self
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePopPan(_:)))
        panGesture.name = "pop"
        view.addGestureRecognizer(panGesture)
    }

    @objc private func handlePushPan(_ gesture: UIPanGestureRecognizer) {
        guard let provider = objc_getAssociatedObject(gesture, "viewControllerProvider") as? (() -> UIViewController) else { return }
        let translation = gesture.translation(in: self.view)
        let percent = max(-translation.x, 0) / self.view.bounds.width

        switch gesture.state {
        case .began:
            if translation.x < 0 {
                interactiveTransition = UIPercentDrivenInteractiveTransition()
                pushViewController(provider(), animated: true)
            }
        case .changed:
            interactiveTransition?.update(percent)
        case .ended, .cancelled:
            if percent > 0.5 {
                interactiveTransition?.finish()
            } else {
                interactiveTransition?.cancel()
            }
            interactiveTransition = nil
        default:
            break
        }
    }

    @objc private func handlePopPan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self.view)
        let percent = max(translation.x, 0) / self.view.bounds.width

        switch gesture.state {
        case .began:
            if translation.x > 0 {
                interactiveTransition = UIPercentDrivenInteractiveTransition()
                popViewController(animated: true)
            }
        case .changed:
            interactiveTransition?.update(percent)
        case .ended, .cancelled:
            if percent > 0.5 {
                interactiveTransition?.finish()
            } else {
                interactiveTransition?.cancel()
            }
            interactiveTransition = nil
        default:
            break
        }
    }

    // MARK: UINavigationControllerDelegate

    public func navigationController(_ navigationController: UINavigationController,
                                     animationControllerFor operation: UINavigationController.Operation,
                                     from fromVC: UIViewController,
                                     to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        if operation == .push {
            return PushAnimator()
        } else if operation == .pop {
            return PopAnimator()
        }
        
        return nil
    }

    public func navigationController(_ navigationController: UINavigationController,
                                     interactionControllerFor animationController: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        return interactiveTransition
    }
}
