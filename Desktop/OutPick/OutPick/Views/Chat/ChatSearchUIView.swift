//
//  ChatSearchUIView.swift
//  OutPick
//
//  Created by 김가윤 on 8/26/25.
//

import Foundation
import UIKit

class ChatSearchUIView: UIView {
    private var messageCountLabel: UILabel = {
        let lb = UILabel()
        lb.text = "검색 결과 없음"
        lb.font = .systemFont(ofSize: 15, weight: .medium)
        lb.textColor = .black
        lb.translatesAutoresizingMaskIntoConstraints = false
        
        return lb
    }()
    
    private var btnContainer: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.alignment = .center
        sv.distribution = .equalCentering
        sv.spacing = 5
        sv.translatesAutoresizingMaskIntoConstraints = false
        
        return sv
    }()
    
    private var upBtn: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "chevron.up"), for: .normal)
        btn.tintColor = .black
        btn.isEnabled = false
        
        return btn
    }()
    
    private var downBtn: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        btn.tintColor = .black
        btn.isEnabled = false
        
        return btn
    }()
    
    private override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        btnContainer.addArrangedSubview(upBtn)
        btnContainer.addArrangedSubview(downBtn)
        addSubview(messageCountLabel)
        addSubview(btnContainer)
        self.backgroundColor = .secondarySystemBackground
        
        NSLayoutConstraint.activate([
//            messageCountLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 30),
            messageCountLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            messageCountLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            btnContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -30),
            btnContainer.centerYAnchor.constraint(equalTo: messageCountLabel.centerYAnchor),
        ])
//        mainContainer.addArrangedSubview(messageCountLabel)
//        mainContainer.addArrangedSubview(btnContainer)
//        addSubview(mainContainer)
    }
}
