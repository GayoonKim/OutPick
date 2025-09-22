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

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    func configure(title: String, subtitle: String, onTap: @escaping () -> Void) {
        self.onTap = onTap
        titleLabel.text = title
        subtitleLabel.text = subtitle
    }

    func show() {
        guard let window = UIApplication.shared.windows.first else { return }
        self.frame = CGRect(x: 0, y: -80, width: window.bounds.width, height: 80)
        backgroundColor = .systemGray6

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        window.addSubview(self)
        
        UIView.animate(withDuration: 0.3) {
            self.frame.origin.y = 0
        }

        // 일정 시간 후 자동 dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.dismiss()
        }
    }

    @objc private func handleTap() {
        onTap?()
        dismiss()
    }

    func dismiss() {
        UIView.animate(withDuration: 0.3, animations: {
            self.frame.origin.y = -self.frame.height
        }) { _ in
            self.removeFromSuperview()
        }
    }
}
