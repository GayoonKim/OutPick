//
//  ChatCustomPopUpMenu.swift
//  OutPick
//
//  Created by 김가윤 on 8/22/25.
//

import UIKit
import Combine

class ChatCustomPopUpMenu: UIView {
    let replyPublisher = PassthroughSubject<Void, Never>()
    let copyPublisher = PassthroughSubject<Void, Never>()
    let deletePublisher = PassthroughSubject<Void, Never>()
    
    private var stackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.alignment = .fill
        sv.distribution = .fillEqually
        sv.spacing = 8
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()
    
    private let replyButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("답장", for: .normal)
        button.setTitleColor(.black, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        return button
    }()
    
    private let copyButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("복사", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        button.setTitleColor(.black, for: .normal)
        return button
    }()
    
    private let deleteButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("삭제", for: .normal)
        button.setTitleColor(.systemRed, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        return button
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setupView()
        setupActions()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    private func setupView() {
        clipsToBounds = true
        
        addSubview(stackView)
        stackView.addArrangedSubview(replyButton)
        stackView.addArrangedSubview(copyButton)
        stackView.addArrangedSubview(deleteButton)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            replyButton.heightAnchor.constraint(equalToConstant: 40),
            replyButton.widthAnchor.constraint(equalToConstant: 200),
            copyButton.heightAnchor.constraint(equalToConstant: 40),
            deleteButton.heightAnchor.constraint(equalToConstant: 40),
        ])
    }
    
    private func setupActions() {
        replyButton.addTarget(self, action: #selector(replyTapped), for: .touchUpInside)
        copyButton.addTarget(self, action: #selector(copyTapped), for: .touchUpInside)
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
    }
    
    @objc private func replyTapped() {
        replyPublisher.send()
    }
    
    @objc private func copyTapped() {
        copyPublisher.send()
    }
    
    @objc private func deleteTapped() {
        deletePublisher.send()
    }
}
