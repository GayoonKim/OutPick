//
//  CustomTabBarView.swift
//  OutPick
//
//  Created by 김가윤 on 5/30/25.
//

import Foundation
import UIKit
import Combine

class CustomTabBarView: UIView {
    
    let tabSelected = PassthroughSubject<Int, Never>()
    private var currentTabIndex: Int?
    
    private var buttons: [UIButton] = [("cloud.sun.fill", "날씨"), ("bubble.left.and.bubble.right.fill", "오픈채팅"), ("bubble.middle.bottom.fill", "채팅"), ("book.fill", "룩북"), ("gearshape.fill", "내 정보")].map{
        let button = TabBarButton(type: .system)
        
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: $0.0)?.withRenderingMode(.alwaysTemplate)
        config.buttonSize = .mini
        config.imagePlacement = .top
        config.imagePadding = 5
        config.baseForegroundColor = .gray
        
        var attrTitle = AttributedString($0.1)
        attrTitle.font = .systemFont(ofSize: 10.0, weight: .medium)
        config.attributedTitle = attrTitle

        button.configuration = config
        
        return button
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setup() {
        backgroundColor = .white
        
        for (index, button) in buttons.enumerated() {
            button.tag = index
            button.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
        }
        
        let stack = UIStackView(arrangedSubviews: buttons)
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    @MainActor
    @objc private func tabTapped(_ sender: UIButton) {
        let index = sender.tag
        updateButtonStates(index)
        currentTabIndex = index
        tabSelected.send(index)
    }
    
    func updateButtonStates(_ selectedIndex: Int) {
        for (index, button) in buttons.enumerated() {
            button.configuration?.baseForegroundColor = (index == selectedIndex) ? .black : .gray
        }
    }
}

private class TabBarButton: UIButton {
    override var isHighlighted: Bool {
        get { false }
        set { }
    }
}
