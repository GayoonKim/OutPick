//
//  ChatBannerView.swift
//  OutPick
//
//  Created by 김가윤 on 9/22/25.
//

import Foundation
import UIKit

final class ChatBannerView: UIView {
    private var onTap: (() -> Void)?
    private var dismissWorkItem: DispatchWorkItem?
    private var hasPresented = false
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.boldSystemFont(ofSize: 14)
        label.textColor = .white
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        return label
    }()
    
    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = .white
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        return label
    }()
    
    private var topConstraint: NSLayoutConstraint?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayout()
    }

    private func setupLayout() {
        let stackView = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
    }
    
    func configure(title: String, subtitle: String, onTap: @escaping () -> Void) {
        self.onTap = onTap
        titleLabel.text = title
        subtitleLabel.text = subtitle
    }
    
    func show() {
        show(retryCount: 6)
    }

    private func show(retryCount: Int) {
        guard !hasPresented else { return }

        guard let window = Self.findHostWindow() else {
            retryShow(remaining: retryCount)
            return
        }

        guard window.bounds.width > 0, window.bounds.height > 0 else {
            retryShow(remaining: retryCount)
            return
        }

        hasPresented = true

        let minBannerHeight: CGFloat = 55
        backgroundColor = .black
        self.layer.cornerRadius = 16
        self.layer.shadowColor = UIColor.black.cgColor
        self.layer.shadowOpacity = 0.3
        self.layer.shadowOffset = CGSize(width: 0, height: 2)
        self.layer.shadowRadius = 4
        
        translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(self)
        window.bringSubviewToFront(self)
        
        topConstraint = topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: -minBannerHeight)
        NSLayoutConstraint.activate([
            topConstraint!,
            leadingAnchor.constraint(equalTo: window.leadingAnchor, constant: 5),
            trailingAnchor.constraint(equalTo: window.trailingAnchor, constant: -5),
            heightAnchor.constraint(greaterThanOrEqualToConstant: minBannerHeight)
        ])
        
        window.layoutIfNeeded()
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        UIView.animate(withDuration: 0.3) {
            self.topConstraint?.constant = 0
            window.layoutIfNeeded()
        }

        // 일정 시간 후 자동 dismiss
        dismissWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }
    
    @objc private func handleTap() {
        onTap?()
        dismiss()
    }
    
    func dismiss() {
        dismissWorkItem?.cancel()
        guard let window = superview else { return }
        UIView.animate(withDuration: 0.3, animations: {
            self.topConstraint?.constant = -(self.frame.height)
            window.layoutIfNeeded()
        }) { _ in
            self.removeFromSuperview()
        }
    }

    private static func findHostWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter {
                $0.activationState == .foregroundActive ||
                $0.activationState == .foregroundInactive
            }

        let sceneWindows = scenes
            .flatMap(\.windows)
            .filter {
                !$0.isHidden &&
                $0.alpha > 0 &&
                $0.windowLevel == .normal &&
                $0.rootViewController != nil
            }

        if let keyWindow = sceneWindows
            .first(where: { $0.isKeyWindow }) {
            return keyWindow
        }

        if let anyWindow = sceneWindows.first {
            return anyWindow
        }

        return UIApplication.shared.windows.first(where: {
            $0.isKeyWindow &&
            $0.windowLevel == .normal &&
            $0.rootViewController != nil
        }) ?? UIApplication.shared.windows.first(where: {
            !$0.isHidden &&
            $0.alpha > 0 &&
            $0.windowLevel == .normal &&
            $0.rootViewController != nil
        })
    }

    private func retryShow(remaining: Int) {
        guard remaining > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.show(retryCount: remaining - 1)
        }
    }
}
