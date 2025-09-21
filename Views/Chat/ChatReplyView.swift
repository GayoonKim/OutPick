//
//  ChatReplyView.swift
//  OutPick
//
//  Created by 김가윤 on 9/9/25.
//

import Foundation
import UIKit

class ChatReplyView: UIView {
    private lazy var senderLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11, weight: .heavy)
        label.translatesAutoresizingMaskIntoConstraints = false
        
        return label
    }()
    
    private lazy var messageLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 9, weight: .light)
        label.translatesAutoresizingMaskIntoConstraints = false
        
        return label
    }()
    
    private lazy var cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "xmark")
        config.buttonSize = .small
        config.imagePlacement = .trailing
        config.baseForegroundColor = .black
        button.configuration = config
        
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        self.layer.cornerRadius = self.frame.height / 2
    }
    
    private func setupViews() {
        self.backgroundColor = .secondarySystemBackground
        
        addSubview(senderLabel)
        addSubview(messageLabel)
        addSubview(cancelButton)
        NSLayoutConstraint.activate([
            senderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            senderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -50),
            messageLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            messageLabel.topAnchor.constraint(equalTo: senderLabel.bottomAnchor, constant: 3),
            
            cancelButton.widthAnchor.constraint(equalToConstant: 16),
            cancelButton.heightAnchor.constraint(equalToConstant: 16),
            cancelButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            cancelButton.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        
        cancelButton.addTarget(self, action: #selector(handleCancel), for: .touchUpInside)
    }
    
    @objc private func handleCancel() {
        self.isHidden = true
    }
    
    func configure(with message: ChatMessage) {
        senderLabel.text = message.senderNickname
        messageLabel.text = message.msg
    }
}
