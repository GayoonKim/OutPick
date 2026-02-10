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
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.boldSystemFont(ofSize: 14)
        label.textColor = .white
        label.numberOfLines = 1
        return label
    }()
    
    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = .white
        label.numberOfLines = 2
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
        stackView.alignment = .leading
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
        let window: UIWindow?
        if let windowScene = UIApplication.shared.connectedScenes
            .filter({ $0.activationState == .foregroundActive })
            .first as? UIWindowScene {
            window = windowScene.windows.first
        } else {
            return
        }
        guard let window = window else { return }

        let bannerHeight: CGFloat = 55
        backgroundColor = .black
        self.layer.cornerRadius = 16
        self.layer.shadowColor = UIColor.black.cgColor
        self.layer.shadowOpacity = 0.3
        self.layer.shadowOffset = CGSize(width: 0, height: 2)
        self.layer.shadowRadius = 4
        
        translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(self)
        
        topConstraint = topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: -bannerHeight)
        NSLayoutConstraint.activate([
            topConstraint!,
            leadingAnchor.constraint(equalTo: window.leadingAnchor, constant: 5),
            trailingAnchor.constraint(equalTo: window.trailingAnchor, constant: -5),
            heightAnchor.constraint(equalToConstant: bannerHeight)
        ])
        
        window.layoutIfNeeded()
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        UIView.animate(withDuration: 0.3) {
            self.topConstraint?.constant = 0
            window.layoutIfNeeded()
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
        guard let window = superview else { return }
        UIView.animate(withDuration: 0.3, animations: {
            self.topConstraint?.constant = -(self.frame.height)
            window.layoutIfNeeded()
        }) { _ in
            self.removeFromSuperview()
        }
    }
}
