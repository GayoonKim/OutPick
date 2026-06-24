//
//  ChatSearchUIView.swift
//  OutPick
//
//  Created by 김가윤 on 8/26/25.
//

import Foundation
import UIKit

class ChatSearchUIView: UIView {
    struct SearchResultState {
        let totalCount: Int
        let displayIndex: Int
        let canMoveToPrevious: Bool
        let canMoveToNext: Bool
    }

    private var messageCountLabel: UILabel = {
        let lb = UILabel()
        lb.text = "검색 결과 없음"
        lb.font = .systemFont(ofSize: 15, weight: .medium)
        lb.textColor = OutPickTheme.ColorToken.textPrimary
        lb.translatesAutoresizingMaskIntoConstraints = false
        
        return lb
    }()
    
    private var btnContainer: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.alignment = .center
        sv.distribution = .equalCentering
        sv.spacing = 10
        sv.translatesAutoresizingMaskIntoConstraints = false
        
        return sv
    }()
    
    private var upBtn: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "chevron.up")?.withTintColor(OutPickTheme.ColorToken.iconPrimary, renderingMode: .alwaysOriginal), for: .normal)
        btn.setImage(UIImage(systemName: "chevron.up")?.withTintColor(OutPickTheme.ColorToken.iconSecondary, renderingMode: .alwaysOriginal), for: .disabled)
        btn.backgroundColor = OutPickTheme.ColorToken.surfaceElevated
        btn.layer.masksToBounds = true
        btn.clipsToBounds = true
        btn.isEnabled = false
        btn.translatesAutoresizingMaskIntoConstraints = false

        return btn
    }()
    
    private var downBtn: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "chevron.down")?.withTintColor(OutPickTheme.ColorToken.iconPrimary, renderingMode: .alwaysOriginal), for: .normal)
        btn.setImage(UIImage(systemName: "chevron.down")?.withTintColor(OutPickTheme.ColorToken.iconSecondary, renderingMode: .alwaysOriginal), for: .disabled)
        btn.backgroundColor = OutPickTheme.ColorToken.surfaceElevated
        btn.layer.masksToBounds = true
        btn.clipsToBounds = true
        btn.isEnabled = false
        btn.translatesAutoresizingMaskIntoConstraints = false

        return btn
    }()
    
    var onPreviousTapped: (() -> Void)?
    var onNextTapped: (() -> Void)?
    
    private override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        layoutIfNeeded()
        
        upBtn.layer.cornerRadius = upBtn.bounds.width / 2
        downBtn.layer.cornerRadius = downBtn.bounds.width / 2
    }
    
    private func setupViews() {
        btnContainer.addArrangedSubview(upBtn)
        btnContainer.addArrangedSubview(downBtn)
        addSubview(messageCountLabel)
        addSubview(btnContainer)
        self.backgroundColor = OutPickTheme.ColorToken.backgroundRaised
        self.layer.borderColor = OutPickTheme.ColorToken.borderSubtle.cgColor
        self.layer.borderWidth = 1
        
        NSLayoutConstraint.activate([
            upBtn.widthAnchor.constraint(equalToConstant: 30),
            upBtn.heightAnchor.constraint(equalToConstant: 30),
            downBtn.widthAnchor.constraint(equalToConstant: 30),
            downBtn.heightAnchor.constraint(equalToConstant: 30),
            
            messageCountLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            messageCountLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            btnContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -30),
            btnContainer.centerYAnchor.constraint(equalTo: messageCountLabel.centerYAnchor),
        ])
        
        upBtn.addTarget(self, action: #selector(upBtnTapped), for: .touchUpInside)
        downBtn.addTarget(self, action: #selector(downBtnTapped), for: .touchUpInside)
    }
    
    @objc private func upBtnTapped() {
        onPreviousTapped?()
    }
    
    @objc private func downBtnTapped() {
        onNextTapped?()
    }
    
    func updateSearchResult(_ state: SearchResultState) {
        if state.totalCount > 0 {
            messageCountLabel.text = "\(state.displayIndex)/\(state.totalCount)"
            upBtn.isEnabled = state.canMoveToPrevious
            downBtn.isEnabled = state.canMoveToNext
        } else {
            // 결과가 없을 때
            messageCountLabel.text = "검색 결과 없음"
            upBtn.isEnabled = false
            downBtn.isEnabled = false
        }
    }
}
