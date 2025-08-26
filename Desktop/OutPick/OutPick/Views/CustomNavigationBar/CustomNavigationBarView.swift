//
//  CustomNavigationBarView.swift
//  OutPick
//
//  Created by 김가윤 on 5/28/25.
//

import Foundation
import UIKit
import Combine

class CustomNavigationBarView: UIView {
    private let leftStack = UIStackView()
    private let centerStack = UIStackView()
    let rightStack = UIStackView()
    
    private let container: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 4
        stackView.distribution = .equalCentering
        
        return stackView
    }()
    
    private let searchContainer: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 4
        stackView.distribution = .equalCentering
        
        return stackView
    }()

    private let searchImgView: UIImageView = {
        let searchImg = UIImage(systemName: "magnifyingglass")
        let imageView = UIImageView(image: searchImg)
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .black
        
        return imageView
    }()
    
    let searchTextField: UITextField = {
        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholder = "대화내용 검색"
        textField.backgroundColor = .secondarySystemBackground
        textField.clearButtonMode = .whileEditing
        textField.heightAnchor.constraint(equalToConstant: 34).isActive = true
        textField.returnKeyType = .search
        
        return textField
    }()
    
    private let cancelBtn: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("취소", for: .normal)
        button.setTitleColor(.black, for: .normal)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        
        return button
    }()

    private let wrapperView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    let searchKeywordPublisher = PassthroughSubject<String, Never>()
    let cancelSearchPublisher = PassthroughSubject<Void, Never>()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setup() {
        backgroundColor = .white
        
        [leftStack, centerStack, rightStack].forEach {
            $0.axis = .horizontal
            $0.spacing = 5
            $0.alignment = .center
        }

        container.addArrangedSubview(leftStack)
        container.addArrangedSubview(centerStack)
        container.addArrangedSubview(rightStack)

        addSubview(container)
        container.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            container.heightAnchor.constraint(equalToConstant: 44),
        ])
        
        addSubview(searchContainer)
        searchContainer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            searchContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            searchContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            searchContainer.topAnchor.constraint(equalTo: topAnchor),
            searchContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            searchContainer.heightAnchor.constraint(equalToConstant: 44),
        ])
        searchContainer.isHidden = true
    }
    
    func configure(leftViews: [UIView], centerViews: [UIView] = [], rightViews: [UIView]) {
        [leftStack, centerStack, rightStack].forEach { $0.arrangedSubviews.forEach { $0.removeFromSuperview() } }
        
        leftViews.forEach { leftStack.addArrangedSubview($0) }
        centerViews.forEach { centerStack.addArrangedSubview($0) }
        rightViews.forEach { rightStack.addArrangedSubview($0) }
    }
    
    func configureForChatRoom(/*unreadCount: Int,*/ roomTitle: String, participantCount: Int, onBack: @escaping () -> Void, onSearch: @escaping () -> Void, onSetting: @escaping () -> Void) {
        container.isHidden = false
        searchContainer.isHidden = true
        
        let backButton = UIButton.navBackButton(action: onBack)
//        let unreadLabel = UILabel.navSubtitle("\(unreadCount)")
        
        let titleLabel = UILabel.navTitle(roomTitle)
        let participantLabel = UILabel.navSubtitle("\(participantCount)명")
        
        let searchButton = UIButton.navButtonIcon("magnifyingglass", action: onSearch)
        let settingButton = UIButton.navButtonIcon("text.justify", action: onSetting)
        
        configure(
            leftViews: [backButton/*, unreadLabel*/],
            centerViews: [titleLabel, participantLabel],
            rightViews: [searchButton, settingButton]
        )
    }
    
    func switchToSearchMode() {
        container.isHidden = true
        searchContainer.isHidden = false
        searchContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }

        searchImgView.setContentHuggingPriority(.required, for: .horizontal)
        searchImgView.setContentCompressionResistancePriority(.required, for: .horizontal)
        
        searchTextField.delegate = self
        
        let leftPaddingView = UIView(frame: CGRect(x: 0, y: 0, width: 8, height: searchTextField.frame.height))
        searchTextField.leftView = leftPaddingView
        searchTextField.leftViewMode = .always
        
        cancelBtn.addTarget(self, action: #selector(cancelBtnTap), for: .touchUpInside)

        wrapperView.addSubview(searchTextField)
        NSLayoutConstraint.activate([
            searchTextField.leadingAnchor.constraint(equalTo: wrapperView.leadingAnchor, constant: 8),
            searchTextField.trailingAnchor.constraint(equalTo: wrapperView.trailingAnchor, constant: -8),
            searchTextField.topAnchor.constraint(equalTo: wrapperView.topAnchor),
            searchTextField.bottomAnchor.constraint(equalTo: wrapperView.bottomAnchor),
        ])
        
        let searchStack = UIStackView(arrangedSubviews: [searchImgView, wrapperView, cancelBtn])
        searchStack.axis = .horizontal
        searchStack.spacing = 8
        searchStack.alignment = .center
        searchStack.distribution = .fill

        searchContainer.addArrangedSubview(searchStack)
        
        searchTextField.becomeFirstResponder()
    }
    
    @objc private func cancelBtnTap() {
        searchContainer.isHidden = true
        searchTextField.resignFirstResponder()
        container.isHidden = false
        
        cancelSearchPublisher.send()
    }
}

extension UIButton {
    static func navButtonIcon(_ name: String, action: @escaping () -> Void) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: name), for: .normal)
        btn.tintColor = .black
        btn.addAction(UIAction { _ in action() }, for: .touchUpInside)
        
        return btn
    }
    
    static func navBackButton(action: @escaping () -> Void) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        btn.tintColor = .black
        btn.addAction(UIAction { _ in action() }, for: .touchUpInside)
        
        return btn
    }
}

extension UILabel {
    static func navTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .boldSystemFont(ofSize: 18)
        label.textColor = .black
        
        return label
    }
    
    static func navSubtitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 12)
        label.textColor = .gray
        
        return label
    }
}

extension CustomNavigationBarView: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard let keyword = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !keyword.isEmpty else { return false }
        
        searchKeywordPublisher.send(keyword)
        return true
    }
}
