//
//  ChatUI.swift
//  OutPick
//
//  Created by 김가윤 on 4/26/25.
//

import Foundation
import UIKit

class ChatUIView: UIView {
    
    private var attachmentButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "plus"), for: .normal)
        button.tintColor = .black
        button.clipsToBounds = true
        button.backgroundColor = UIColor(white: 0.1, alpha: 0.05)
        button.translatesAutoresizingMaskIntoConstraints = false
        
        return button
    }()
    
    private var messageTextView: UITextView = {
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
        textView.textContainerInset = UIEdgeInsets(top: 13, left: 12, bottom: 13, right: 12)
        
        return textView
    }()
    
    private var sendButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "paperplane"), for: .normal)
        button.isEnabled = false
        button.clipsToBounds = true
        button.backgroundColor = UIColor(white: 0.1, alpha: 0.05)
        button.translatesAutoresizingMaskIntoConstraints = false
        
        return button
    }()
    
    private var messageTextViewHeightConstraint: NSLayoutConstraint!
    
    var textView: UITextView {
        return messageTextView
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
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
        
        NSLayoutConstraint.activate([
            attachmentButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            attachmentButton.centerYAnchor.constraint(equalTo: bottomAnchor, constant: -22),
            attachmentButton.widthAnchor.constraint(equalToConstant: 40),
            attachmentButton.heightAnchor.constraint(equalTo: attachmentButton.widthAnchor),

            messageTextView.leadingAnchor.constraint(equalTo: attachmentButton.trailingAnchor, constant: 5),
            messageTextView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -5),
            messageTextView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            
            sendButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            sendButton.centerYAnchor.constraint(equalTo: bottomAnchor, constant: -22),
            sendButton.widthAnchor.constraint(equalToConstant: 40),
            sendButton.heightAnchor.constraint(equalTo: sendButton.widthAnchor),
        ])
        
        messageTextView.delegate = self
        messageTextViewHeightConstraint = messageTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 40)
        messageTextViewHeightConstraint.priority = .defaultLow
        messageTextViewHeightConstraint.isActive = true
    }
}

extension ChatUIView: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        let size = CGSize(width: textView.frame.width, height: .infinity)
        let estimatedSize = textView.sizeThatFits(size)
        
        let maxHeight: CGFloat = 120
        
        messageTextView.isScrollEnabled = estimatedSize.height > maxHeight
        
        messageTextViewHeightConstraint.isActive = false
        messageTextViewHeightConstraint = messageTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: min(estimatedSize.height, maxHeight))
        messageTextViewHeightConstraint.isActive = true
        
        layoutIfNeeded()
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
