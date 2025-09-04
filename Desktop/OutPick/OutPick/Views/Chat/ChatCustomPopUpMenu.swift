//
//  ChatCustomPopUpMenu.swift
//  OutPick
//
//  Created by 김가윤 on 8/22/25.
//

import UIKit
import Combine

class ChatCustomPopUpMenu: UIView {
    var onReply: (() -> Void)?
    var onCopy: (() -> Void)?
    var onDelete: (() -> Void)?
    
    private var mainSV: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.alignment = .fill
        sv.distribution = .fillProportionally
        sv.spacing = 8
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let replyButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("답장", for: .normal)
        button.semanticContentAttribute = .forceRightToLeft
        button.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        button.tintColor = .white
        
        let config = UIImage.SymbolConfiguration(pointSize: 10)
        let image = UIImage(systemName: "arrowshape.turn.up.right.fill", withConfiguration: config)?.withRenderingMode(.alwaysTemplate)
        button.setImage(image, for: .normal)
        button.titleEdgeInsets = UIEdgeInsets(top: 0, left: -50, bottom: 0, right: 50)
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: 50, bottom: 0, right: -50)
        //        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 50, bottom: 0, right: -50)

        return button
    }()

    private let copyButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("복사", for: .normal)
        button.semanticContentAttribute = .forceRightToLeft
        button.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        button.tintColor = .white
        
        let config = UIImage.SymbolConfiguration(pointSize: 10)
        let image = UIImage(systemName: "document.on.clipboard", withConfiguration: config)?.withRenderingMode(.alwaysTemplate)
        button.setImage(image, for: .normal)
        button.titleEdgeInsets = UIEdgeInsets(top: 0, left: -50, bottom: 0, right: 50)
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: 50, bottom: 0, right: -50)
        
        return button
    }()
    
    private let deleteButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("삭제", for: .normal)
        button.semanticContentAttribute = .forceRightToLeft
        button.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        button.tintColor = .red
        
        let config = UIImage.SymbolConfiguration(pointSize: 10)
        let image = UIImage(systemName: "exclamationmark.triangle", withConfiguration: config)?.withRenderingMode(.alwaysTemplate)
        button.setImage(image, for: .normal)
        button.titleEdgeInsets = UIEdgeInsets(top: 0, left: -50, bottom: 0, right: 50)
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: 50, bottom: 0, right: -50)
        
        return button
    }()
    
    private func makeSeparator() -> UIView {
        let view = UIView()
        view.backgroundColor = .white
        view.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true
        return view
    }
    
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
        
        addSubview(mainSV)
        mainSV.addArrangedSubview(replyButton)
        mainSV.addArrangedSubview(makeSeparator())
        mainSV.addArrangedSubview(copyButton)
        mainSV.addArrangedSubview(makeSeparator())
        mainSV.addArrangedSubview(deleteButton)
        
        NSLayoutConstraint.activate([
            mainSV.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            mainSV.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            mainSV.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            mainSV.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            
            replyButton.widthAnchor.constraint(equalToConstant: UIScreen.main.bounds.width * 0.4),
            copyButton.widthAnchor.constraint(equalToConstant: UIScreen.main.bounds.width * 0.4),
            deleteButton.widthAnchor.constraint(equalToConstant: UIScreen.main.bounds.width * 0.4),
            replyButton.heightAnchor.constraint(equalToConstant: UIScreen.main.bounds.width * 0.05),
            copyButton.heightAnchor.constraint(equalTo: replyButton.heightAnchor),
            deleteButton.heightAnchor.constraint(equalTo: replyButton.heightAnchor),
        ])
    }
    
    private func setupActions() {
        replyButton.addTarget(self, action: #selector(replyTapped), for: .touchUpInside)
        copyButton.addTarget(self, action: #selector(copyTapped), for: .touchUpInside)
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
    }
    
    @objc private func replyTapped() {
        onReply?()
    }
    
    @objc private func copyTapped() {
        onCopy?()
    }
    
    @objc private func deleteTapped() {
        onDelete?()
    }
}
