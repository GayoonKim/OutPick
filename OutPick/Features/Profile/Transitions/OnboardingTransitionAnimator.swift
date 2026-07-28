import UIKit

final class OnboardingTransitionAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let operation: UINavigationController.Operation

    init(operation: UINavigationController.Operation) {
        self.operation = operation
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        UIAccessibility.isReduceMotionEnabled ? 0.2 : 0.38
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard let fromView = transitionContext.view(forKey: .from),
              let toView = transitionContext.view(forKey: .to),
              let toViewController = transitionContext.viewController(forKey: .to) else {
            transitionContext.completeTransition(false)
            return
        }

        let container = transitionContext.containerView
        let isPush = operation == .push
        container.insertSubview(toView, aboveSubview: fromView)
        toView.frame = transitionContext.finalFrame(for: toViewController)
        toView.alpha = 0

        if UIAccessibility.isReduceMotionEnabled == false {
            toView.transform = CGAffineTransform(translationX: isPush ? 28 : -28, y: 0)
        }

        UIView.animate(
            withDuration: transitionDuration(using: transitionContext),
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState]
        ) {
            toView.alpha = 1
            toView.transform = .identity
            fromView.alpha = 0.72
            if UIAccessibility.isReduceMotionEnabled == false {
                fromView.transform = CGAffineTransform(
                    translationX: isPush ? -12 : 12,
                    y: 0
                )
            }
        } completion: { _ in
            fromView.alpha = 1
            fromView.transform = .identity
            transitionContext.completeTransition(transitionContext.transitionWasCancelled == false)
        }
    }
}
