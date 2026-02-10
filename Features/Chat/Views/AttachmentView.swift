//
//  ChatAttachmentView.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import UIKit

class AttachmentView: UIView {
    var onButtonTapped: ((String) -> Void)?
    
    private let stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 30
        stackView.distribution = .equalSpacing
        stackView.alignment = .center
        stackView.tag = 99
        return stackView
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupAttachmentView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupAttachmentView() {
        backgroundColor = UIColor(white: 0.1, alpha: 0.05)
        layer.cornerRadius = 20
        isHidden = true
        
        addSubview(stackView)
        
        for btn in ["photo", "camera" ] {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: btn), for: .normal)
            button.tintColor = .black
            button.backgroundColor = .white
            button.accessibilityIdentifier = btn
            button.addTarget(self, action: #selector(btnTapped), for: .touchUpInside)
            
            button.translatesAutoresizingMaskIntoConstraints = false
            button.clipsToBounds = true
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 50),
                button.heightAnchor.constraint(equalToConstant: 50)
            ])
            button.layer.cornerRadius = 25
            
            stackView.addArrangedSubview(button)
        }
        
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -40),
            stackView.heightAnchor.constraint(equalToConstant: 75)
        ])
    }
    
    @objc private func btnTapped(_ sender: UIButton) {
        guard let identifier = sender.accessibilityIdentifier else { return }
        onButtonTapped?(identifier)
    }
}
