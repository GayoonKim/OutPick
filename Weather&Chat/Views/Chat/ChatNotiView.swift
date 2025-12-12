//
//  ChatCopyView.swift
//  OutPick
//
//  Created by 김가윤 on 9/9/25.
//

import Foundation
import UIKit

class ChatNotiView: UIView {
    private lazy var container: UIView = {
        let view = UIView()
        view.backgroundColor = .darkGray
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    private lazy var notiLabel: UILabel = {
        let lb = UILabel()
        lb.font = .systemFont(ofSize: 15, weight: .light)
        lb.textColor = .white
        lb.translatesAutoresizingMaskIntoConstraints = false
        
        return lb
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(_ text: String) {
        notiLabel.text = text
    }
    
    private func setupViews() {
        addSubview(container)
        container.addSubview(notiLabel)
        container.alpha = 0.5
        container.layer.opacity = 0.5
        
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            notiLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            notiLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
    }
}
