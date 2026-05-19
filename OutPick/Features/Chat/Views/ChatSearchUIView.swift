//
//  ChatSearchUIView.swift
//  OutPick
//
//  Created by 김가윤 on 8/26/25.
//

import Foundation
import UIKit
import Combine

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
        sv.spacing = 10
        sv.translatesAutoresizingMaskIntoConstraints = false
        
        return sv
    }()
    
    private var upBtn: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "chevron.up")?.withTintColor(.black, renderingMode: .alwaysOriginal), for: .normal)
        btn.setImage(UIImage(systemName: "chevron.up")?.withTintColor(.lightGray, renderingMode: .alwaysOriginal), for: .disabled)
        btn.backgroundColor = .white
        btn.layer.masksToBounds = true
        btn.clipsToBounds = true
        btn.isEnabled = false
        btn.translatesAutoresizingMaskIntoConstraints = false

        return btn
    }()
    
    private var downBtn: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "chevron.down")?.withTintColor(.black, renderingMode: .alwaysOriginal), for: .normal)
        btn.setImage(UIImage(systemName: "chevron.down")?.withTintColor(.lightGray, renderingMode: .alwaysOriginal), for: .disabled)
        btn.backgroundColor = .white
        btn.layer.masksToBounds = true
        btn.clipsToBounds = true
        btn.isEnabled = false
        btn.translatesAutoresizingMaskIntoConstraints = false

        return btn
    }()
    
    let upPublisher = PassthroughSubject<Void, Never>()
    let downPublisher = PassthroughSubject<Void, Never>()
    
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
        self.backgroundColor = .secondarySystemBackground
        
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
        upPublisher.send()
    }
    
    @objc private func downBtnTapped() {
        downPublisher.send()
    }
    
    func updateSearchResult(_ count: Int, _ index: Int) {
        if count > 0 {
            messageCountLabel.text = "\(count-index+1)/\(count)"
            
            if count == 1 {
                // 결과가 하나뿐이면 버튼 모두 비활성화
                upBtn.isEnabled = false
                downBtn.isEnabled = false
            } else {
                // 여러 개일 때 현재 위치에 따라 활성화 상태 변경
                if index <= 1 {
                    // 첫 번째 결과 → 위로 이동 불가
                    upBtn.isEnabled = false
                    downBtn.isEnabled = true
                } else if index >= count {
                    // 마지막 결과 → 아래로 이동 불가
                    upBtn.isEnabled = true
                    downBtn.isEnabled = false
                } else {
                    // 중간 위치 → 모두 이동 가능
                    upBtn.isEnabled = true
                    downBtn.isEnabled = true
                }
            }
        } else {
            // 결과가 없을 때
            messageCountLabel.text = "검색 결과 없음"
            upBtn.isEnabled = false
            downBtn.isEnabled = false
        }
    }
}
