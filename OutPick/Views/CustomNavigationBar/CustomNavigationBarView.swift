//
//  CustomNavigationBarView.swift
//  OutPick
//
//  Created by 김가윤 on 5/28/25.
//

import Foundation
import UIKit

class CustomNavigationBarView: UIView {
    let leftStack = UIStackView()
    let centerStack = UIStackView()
    let rightStack = UIStackView()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setup() {
        backgroundColor = .white
        
        [leftStack, centerStack, rightStack].forEach {
            $0.axis = .horizontal
            $0.spacing = 5
            $0.alignment = .center
        }
        
        let container = UIStackView(arrangedSubviews: [leftStack, UIView(), centerStack, UIView(), rightStack])
        container.axis = .horizontal
        container.alignment = .center
        container.spacing = 4
        container.distribution = .equalCentering
        
        addSubview(container)
        container.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            container.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
    
    func configure(leftViews: [UIView], centerViews: [UIView] = [], rightViews: [UIView]) {
        [leftStack, centerStack, rightStack].forEach { $0.arrangedSubviews.forEach { $0.removeFromSuperview() } }
        
        leftViews.forEach { leftStack.addArrangedSubview($0) }
        centerViews.forEach { centerStack.addArrangedSubview($0) }
        rightViews.forEach { rightStack.addArrangedSubview($0) }
    }
    
    func configureForChatRoom(unreadCount: Int, roomTitle: String, participantCount: Int, onBack: @escaping () -> Void, onSearch: @escaping () -> Void, onSetting: @escaping () -> Void) {
        let backButton = UIButton.navBackButton(action: onBack)
        let unreadLabel = UILabel.navSubtitle("\(unreadCount)")
        
        let titleLabel = UILabel.navTitle(roomTitle)
        let participantLabel = UILabel.navSubtitle("\(participantCount)명")
        
        let searchButton = UIButton.navButtonIcon("magnifyingglass", action: onSearch)
        let settingButton = UIButton.navButtonIcon("text.justify", action: onSetting)
        
        configure(
            leftViews: [backButton, unreadLabel],
            centerViews: [titleLabel, participantLabel],
            rightViews: [searchButton, settingButton]
        )
    }
}

extension UIButton {
    static func navButtonIcon(_ name: String, action: @escaping () -> Void) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: name), for: .normal)
        btn.tintColor = .black
        btn.addAction(UIAction { _ in action() }, for: .touchUpInside)
        
        return btn
    }
    
    static func navBackButton(action: @escaping () -> Void) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        btn.tintColor = .black
        btn.addAction(UIAction { _ in action() }, for: .touchUpInside)
        
        return btn
    }
}

extension UILabel {
    static func navTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .boldSystemFont(ofSize: 18)
        label.textColor = .black
        
        return label
    }
    
    static func navSubtitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 12)
        label.textColor = .gray
        
        return label
    }
}
