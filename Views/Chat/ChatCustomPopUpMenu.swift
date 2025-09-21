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
    var onReport: (() -> Void)?
    
    enum PrimaryActionMode { case delete, report }
    private var primaryActionMode: PrimaryActionMode = .delete
    
    private var mainSV: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.alignment = .fill
        sv.distribution = .fillProportionally
        sv.spacing = 8
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    // exclamationmark.triangle
    private lazy var replyButton = UIButton.menuButton(title: "답장", systemImageName: "arrowshape.turn.up.right.fill")
    private lazy var copyButton = UIButton.menuButton(title: "복사", systemImageName: "document.on.clipboard")
    private lazy var deleteButton = UIButton.menuButton(title: "삭제", systemImageName: "trash", tintColor: .red, isDestructive: true)

    private func setPrimaryAction(_ mode: PrimaryActionMode) {
        self.primaryActionMode = mode
        switch mode {
        case .delete:
            deleteButton.configuration = .menuButton(title: "삭제", systemImageName: "trash", isDestructive: true)
            deleteButton.accessibilityIdentifier = "삭제"
        case .report:
            deleteButton.configuration = .menuButton(title: "신고", systemImageName: "exclamationmark.bubble", isDestructive: true)
            deleteButton.accessibilityIdentifier = "신고"
        }
    }
    
    func configurePrimaryActionMode(canDelete: Bool) {
        setPrimaryAction(canDelete ? .delete : .report)
    }
    
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
        switch primaryActionMode {
        case .delete:
            onDelete?()
        case .report:
            onReport?()
        }
    }
}

extension UIButton.Configuration {
    static func menuButton(title: String, systemImageName: String, isDestructive: Bool = false) -> UIButton.Configuration {
        let symBolConfig = UIImage.SymbolConfiguration(pointSize: 10)
        let image = UIImage(systemName: systemImageName, withConfiguration: symBolConfig)?.withRenderingMode(.alwaysTemplate)
        
        var config = UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 5, bottom: 5, trailing: 5)
        config.image = image
        config.imagePlacement = .trailing
        config.imagePadding = 100
        
        var attrTitle = AttributedString(title)
        attrTitle.font = .systemFont(ofSize: 12.0, weight: .medium)
        config.attributedTitle = attrTitle
        config.titleAlignment = .leading
        config.baseForegroundColor = isDestructive ? .red : .white
        
        return config
    }
}

extension UIButton {
    static func menuButton(title: String, systemImageName: String, tintColor: UIColor = .white, isDestructive: Bool = false) -> UIButton {
        let btn = UIButton(type: .system)
        btn.configuration = .menuButton(title: title, systemImageName: systemImageName, isDestructive: isDestructive)
        
        return btn
    }
}
