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
        button.backgroundColor = .secondarySystemBackground
        button.accessibilityIdentifier = "attachmentButton"
        button.translatesAutoresizingMaskIntoConstraints = false
        
        return button
    }()
    
    private(set) var messageTextView: UITextView = {
        let textView = UITextView()
        textView.text = "메시지 입력"
        textView.textColor = .lightGray
        textView.font = UIFont.systemFont(ofSize: 12)
        textView.isScrollEnabled = false
        textView.layer.cornerRadius = 18
        textView.backgroundColor = .secondarySystemBackground
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = UIEdgeInsets(top: 13.5, left: 15, bottom: 13.5, right: 15)

        return textView
    }()
    
    private(set) var sendButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "paperplane"), for: .normal)
        button.tintColor = .black
        button.isEnabled = false
        button.clipsToBounds = true
        button.backgroundColor = .secondarySystemBackground
        button.accessibilityIdentifier = "sendButton"
        button.translatesAutoresizingMaskIntoConstraints = false
        
        return button
    }()
    
    private var container: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    private var messageTextViewHeightConstraint: NSLayoutConstraint!
    
    private(set) var minHeight: CGFloat = 40
    private(set) var maxHeight: CGFloat = 120
    
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
        
        attachmentButton.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
        sendButton.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
        
        NSLayoutConstraint.activate([
            attachmentButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            attachmentButton.widthAnchor.constraint(equalToConstant: minHeight),
            attachmentButton.heightAnchor.constraint(equalTo: attachmentButton.widthAnchor),
            attachmentButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),

            messageTextView.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            messageTextView.leadingAnchor.constraint(equalTo: attachmentButton.trailingAnchor, constant: 10),
            messageTextView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -10),
            messageTextView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            
            sendButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            sendButton.widthAnchor.constraint(equalToConstant: minHeight),
            sendButton.heightAnchor.constraint(equalTo: sendButton.widthAnchor),
            sendButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5)
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
    func updateHeight() {
        let size = CGSize(width: messageTextView.frame.width, height: .infinity)
        let estimatedSize = messageTextView.sizeThatFits(size)
        
        messageTextView.isScrollEnabled = estimatedSize.height > maxHeight

        messageTextViewHeightConstraint.isActive = false
        messageTextViewHeightConstraint = messageTextView.heightAnchor.constraint(equalToConstant: min(estimatedSize.height, maxHeight))
        messageTextViewHeightConstraint.isActive = true
        
        layoutIfNeeded()
    }
    
    func textViewDidChange(_ textView: UITextView) {
        DispatchQueue.main.async {
            if self.messageTextView.text.isEmpty {
                self.sendButton.isEnabled = false
            } else {
                self.sendButton.isEnabled = true
            }
            
            self.updateHeight()
        }
    }
    
    func textViewDidBeginEditing(_ textView: UITextView) {
        DispatchQueue.main.async {
            if textView.textColor == .lightGray {
                textView.text = ""
                textView.textColor = .black
            }
            
            self.updateHeight()
        }
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        DispatchQueue.main.async {
            if textView.text.isEmpty {
                textView.text = "메시지 입력"
                textView.textColor = .lightGray
            }
            
            self.updateHeight()
        }
    }
}
