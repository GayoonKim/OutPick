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
    
    private var buttons: [UIButton] = ["cloud.sun.fill", "bubble.left.and.bubble.right.fill", "bubble.middle.bottom.fill", "magnifyingglass", "gearshape.fill"].map{
        let button = TabBarButton(type: .system)
        button.setImage(UIImage(systemName: $0), for: .normal)
        button.tintColor = .gray
        
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
        tabSelected.send(index)
        currentTabIndex = index
    }
    
    func updateButtonStates(_ selectedIndex: Int) {
        for (index, button) in buttons.enumerated() {
            button.tintColor = (index == selectedIndex) ? .black : .gray
        }
    }
}

private class TabBarButton: UIButton {
    override var isHighlighted: Bool {
        get { false }
        set { }
    }
}
