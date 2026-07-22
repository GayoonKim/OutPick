//
//  ChatNavigationController.swift
//  OutPick
//

import UIKit

@MainActor
protocol ChatInteractivePopControlling: AnyObject {
    var allowsChatInteractivePop: Bool { get }
}

@MainActor
final class ChatNavigationController: UINavigationController, UIGestureRecognizerDelegate {
    override func viewDidLoad() {
        super.viewDidLoad()

        interactivePopGestureRecognizer?.delegate = self
        interactivePopGestureRecognizer?.isEnabled = true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === interactivePopGestureRecognizer else { return true }
        guard viewControllers.count > 1, transitionCoordinator == nil else { return false }

        if let controller = topViewController as? ChatInteractivePopControlling {
            return controller.allowsChatInteractivePop
        }

        return true
    }
}
