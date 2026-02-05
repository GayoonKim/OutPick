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

    // Single overlay container to avoid duplicates
    private var overlayView: UIView?
    private var spinner: UIActivityIndicatorView?

    private init() {}

    // MARK: - Public API

    /// Start on the current top-most view controller (safe default).
    func start() {
        guard let hostView = LoadingIndicator.findHostView() else { return }
        start(in: hostView)
    }

    /// Start on a specific view controller.
    func start(on viewController: UIViewController) {
        start(in: viewController.view)
    }

    /// Stop and remove the overlay/spinner.
    func stop() {
        DispatchQueue.main.async {
            self.spinner?.stopAnimating()
            self.overlayView?.removeFromSuperview()
            self.spinner = nil
            self.overlayView = nil
        }
    }

    /// Whether the indicator is currently visible.
    var isLoading: Bool {
        return overlayView != nil
    }

    // MARK: - Internal

    private func start(in hostView: UIView) {
        DispatchQueue.main.async {
            // If already showing, do nothing (idempotent)
            guard self.overlayView == nil else { return }

            // Container overlay
            let overlay = UIView(frame: hostView.bounds)
            overlay.translatesAutoresizingMaskIntoConstraints = false
            overlay.backgroundColor = .clear
            overlay.isUserInteractionEnabled = false
            overlay.accessibilityIdentifier = "LoadingIndicatorOverlay"

            // Single spinner
            let spinner = UIActivityIndicatorView(style: .large)
            spinner.translatesAutoresizingMaskIntoConstraints = false
            spinner.hidesWhenStopped = true
            spinner.color = .gray
            spinner.accessibilityIdentifier = "LoadingIndicator"

            overlay.addSubview(spinner)
            hostView.addSubview(overlay)

            NSLayoutConstraint.activate([
                overlay.topAnchor.constraint(equalTo: hostView.topAnchor),
                overlay.bottomAnchor.constraint(equalTo: hostView.bottomAnchor),
                overlay.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
                overlay.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),

                spinner.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
                spinner.centerYAnchor.constraint(equalTo: overlay.centerYAnchor)
            ])

            spinner.startAnimating()

            self.overlayView = overlay
            self.spinner = spinner
        }
    }

    // Find a reasonable host view to attach the indicator without a parameter.
    private static func findHostView() -> UIView? {
        // Prefer the key window of the foreground active scene.
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }

        if let window = scenes.first?.windows.first(where: { $0.isKeyWindow }) {
            return window.rootViewController?.view ?? window
        }

        // Fallback to any keyWindow known
        if let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) {
            return window.rootViewController?.view ?? window
        }

        return UIApplication.shared.windows.first?.rootViewController?.view
    }
}
