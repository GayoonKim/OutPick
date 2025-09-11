//
//  ChatCopyView.swift
//  OutPick
//
//  Created by 김가윤 on 9/9/25.
//

import Foundation
import UIKit

class ChatCopyView: UIView {
    private lazy var container: UIView = {
        let view = UIView()
        view.backgroundColor = .darkGray
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    private lazy var copyLabel: UILabel = {
        let lb = UILabel()
        lb.font = .systemFont(ofSize: 15, weight: .light)
        lb.text = "메시지가 복사되었습니다."
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
    
    private func setupViews() {
        addSubview(container)
        container.addSubview(copyLabel)
        container.alpha = 0.5
        container.layer.opacity = 0.5
        
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            copyLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            copyLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
    }
}
