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
        textView.backgroundColor = UIColor(white: 0.95, alpha: 1)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 10, right: 12)
        
        return textView
    }()
    
    private var sendButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "paperplane"), for: .normal)
        button.isEnabled = false
        button.translatesAutoresizingMaskIntoConstraints = false
        
        return button
    }()
    
    private var messageTextViewHeightConstraint: NSLayoutConstraint!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupChatUIView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupChatUIView() {
        backgroundColor = .purple
        layer.masksToBounds = true
        
        addSubview(attachmentButton)
        addSubview(messageTextView)
        addSubview(sendButton)
        
        NSLayoutConstraint.activate([
            attachmentButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            attachmentButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            attachmentButton.widthAnchor.constraint(equalToConstant: 47),
            attachmentButton.heightAnchor.constraint(equalToConstant: 34.33),
            
//            messageTextView.widthAnchor.constraint(equalToConstant: 300),
//            messageTextView.heightAnchor.constraint(equalToConstant: 30.33),
            messageTextView.leadingAnchor.constraint(equalTo: attachmentButton.trailingAnchor),
            messageTextView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor),
            messageTextView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            messageTextView.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            
            sendButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            sendButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 50.67),
            sendButton.heightAnchor.constraint(equalToConstant: 34.33),
        ])
        
        messageTextView.delegate = self
        messageTextViewHeightConstraint = messageTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
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
        messageTextViewHeightConstraint.constant = min(estimatedSize.height, maxHeight)
        
        layoutIfNeeded()
    }
}
