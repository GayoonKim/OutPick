//
//  KeyboardDismissSupport.swift
//  OutPick
//
//  Created by Codex on 7/10/26.
//

import ObjectiveC
import SwiftUI
import UIKit

private var keyboardDismissTapHandlerKey: UInt8 = 0

private final class KeyboardDismissTapHandler: NSObject, UIGestureRecognizerDelegate {
    weak var targetView: UIView?

    init(targetView: UIView) {
        self.targetView = targetView
    }

    @objc func handleTap(_ gestureRecognizer: UITapGestureRecognizer) {
        guard gestureRecognizer.state == .ended else { return }
        targetView?.endEditing(true)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        var touchedView: UIView? = touch.view

        while let currentView = touchedView {
            if currentView is UITextField || currentView is UITextView {
                return false
            }

            touchedView = currentView.superview
        }

        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

extension UIView {
    func installKeyboardDismissTapGesture() {
        if objc_getAssociatedObject(self, &keyboardDismissTapHandlerKey) != nil {
            return
        }

        let handler = KeyboardDismissTapHandler(targetView: self)
        let gesture = UITapGestureRecognizer(
            target: handler,
            action: #selector(KeyboardDismissTapHandler.handleTap(_:))
        )
        gesture.cancelsTouchesInView = false
        gesture.delegate = handler
        addGestureRecognizer(gesture)

        objc_setAssociatedObject(
            self,
            &keyboardDismissTapHandlerKey,
            handler,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }
}

extension UIViewController {
    func installKeyboardDismissTapGesture() {
        view.installKeyboardDismissTapGesture()
    }
}

private struct KeyboardDismissTapInstallerView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            guard let targetView = uiView.window ?? uiView.superview else { return }
            targetView.installKeyboardDismissTapGesture()
        }
    }
}

extension View {
    func outpickDismissKeyboardOnTap() -> some View {
        background(KeyboardDismissTapInstallerView())
    }
}
