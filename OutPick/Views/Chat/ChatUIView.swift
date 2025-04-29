//
//  ChatUI.swift
//  OutPick
//
//  Created by 김가윤 on 4/26/25.
//

import Foundation
import UIKit

class ChatUIView: UIView {
    var onButtonTapped: ((String) -> Void)?
    
    private(set) var attachmentButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "plus"), for: .normal)
        button.tintColor = .black
        button.clipsToBounds = true
        button.backgroundColor = UIColor(white: 0.1, alpha: 0.05)
        button.accessibilityIdentifier = "attachmentButton"
        button.translatesAutoresizingMaskIntoConstraints = false
        
        return button
    }()
    
    private(set) var messageTextView: UITextView = {
        let textView = UITextView()
        textView.text = "메시지를 입력하세요."
        textView.textColor = .lightGray
        textView.font = UIFont.systemFont(ofSize: 12)
        textView.isScrollEnabled = false
        textView.layer.cornerRadius = 18
        textView.backgroundColor = UIColor(white: 0.1, alpha: 0.05)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = UIEdgeInsets(top: 14, left: 15, bottom: 15, right: 15)
        
        return textView
    }()
    
    private(set) var sendButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "paperplane"), for: .normal)
        button.tintColor = .black
        button.isEnabled = false
        button.clipsToBounds = true
        button.backgroundColor = UIColor(white: 0.1, alpha: 0.05)
        button.accessibilityIdentifier = "sendButton"
        button.translatesAutoresizingMaskIntoConstraints = false
        
        return button
    }()
    
    private var messageTextViewHeightConstraint: NSLayoutConstraint!
    
    private(set) var minHeight: CGFloat = 50
    private(set) var maxHeight: CGFloat = 120
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .yellow
        setupChatUIView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        attachmentButton.layer.cornerRadius = attachmentButton.frame.height / 2
        sendButton.layer.cornerRadius = sendButton.frame.height / 2
    }
    
    
    private func setupChatUIView() {
        layer.masksToBounds = true
        
        addSubview(attachmentButton)
        addSubview(messageTextView)
        addSubview(sendButton)
        
        attachmentButton.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
        sendButton.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
        
        NSLayoutConstraint.activate([
            
            attachmentButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            attachmentButton.centerYAnchor.constraint(equalTo: bottomAnchor, constant: -minHeight / 2),
            attachmentButton.widthAnchor.constraint(equalToConstant: 40),
            attachmentButton.heightAnchor.constraint(equalTo: attachmentButton.widthAnchor),

            messageTextView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 3),
            messageTextView.leadingAnchor.constraint(equalTo: attachmentButton.trailingAnchor, constant: 5),
            messageTextView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -5),
            messageTextView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            messageTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight),
            
            sendButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            sendButton.centerYAnchor.constraint(equalTo: bottomAnchor, constant: -minHeight / 2),
            sendButton.widthAnchor.constraint(equalToConstant: 40),
            sendButton.heightAnchor.constraint(equalTo: sendButton.widthAnchor),
            
        ])
        
        messageTextView.delegate = self
        messageTextViewHeightConstraint = messageTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 40)
        messageTextViewHeightConstraint.priority = .defaultHigh
        messageTextViewHeightConstraint.isActive = true
    }
    
    @objc private func buttonTapped(_ sender: UIButton) {
        guard let identifier = sender.accessibilityIdentifier else { return }
        onButtonTapped?(identifier)
    }
    
}

extension ChatUIView: UITextViewDelegate {
    private func updateHeight() {
        let size = CGSize(width: messageTextView.frame.width, height: .infinity)
        let estimatedSize = messageTextView.sizeThatFits(size)
        
        messageTextView.isScrollEnabled = estimatedSize.height > maxHeight
        
        messageTextViewHeightConstraint.isActive = false
        messageTextViewHeightConstraint = messageTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: min(estimatedSize.height, maxHeight))
        messageTextViewHeightConstraint.isActive = true
        
        layoutIfNeeded()
    }
    
    func textViewDidChange(_ textView: UITextView) {
        
        if messageTextView.text.isEmpty {
            sendButton.isEnabled = false
        } else {
            sendButton.isEnabled = true
        }
        
        updateHeight()
    }
    
    func textViewDidBeginEditing(_ textView: UITextView) {
        if textView.textColor == .lightGray {
            textView.text = ""
            textView.textColor = .black
        }
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        if textView.text.isEmpty {
            textView.text = "메시지를 입력하세요."
            textView.textColor = .lightGray
        }
    }
}
