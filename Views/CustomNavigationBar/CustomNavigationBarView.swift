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
    
    private lazy var searchBtn: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "magnifyingglass")
        config.buttonSize = .small
        config.imagePlacement = .leading
        config.baseForegroundColor = .black
        
        button.configuration = config
        button.backgroundColor = .secondarySystemBackground
        button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        button.clipsToBounds = true
        button.layer.cornerRadius = 10
        
        return button
    }()
    
    private lazy var settingBtn: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "text.justify")
        config.buttonSize = .small
        config.imagePlacement = .leading
        config.baseForegroundColor = .black
        
        button.configuration = config
        button.backgroundColor = .secondarySystemBackground
        button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        button.clipsToBounds = true
        button.layer.cornerRadius = 10
        
        return button
    }()
    
    private lazy var backBtn: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "chevron.left")
        config.buttonSize = .small
        config.imagePlacement = .leading
        config.baseForegroundColor = .black
        
        button.configuration = config
        button.backgroundColor = .secondarySystemBackground
        button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        button.clipsToBounds = true
        button.layer.cornerRadius = 10
        
        return button
    }()
    
    private lazy var createBtn: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "plus")
        config.buttonSize = .small
        config.imagePlacement = .leading
        config.baseForegroundColor = .black
        config.imagePadding = 5
        
        var attrTitle = AttributedString("채팅방")
        attrTitle.font = .systemFont(ofSize: 12.0, weight: .heavy)
        config.attributedTitle = attrTitle
        config.titleAlignment = .trailing
        config.baseForegroundColor = .black
        
        button.configuration = config
        button.backgroundColor = .secondarySystemBackground
        button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        button.clipsToBounds = true
        button.layer.cornerRadius = 10
        
        return button
    }()
    
    private lazy var notificationBtn: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "bell.fill")
        config.buttonSize = .small
        config.imagePlacement = .leading
        config.baseForegroundColor = .black
        
        button.configuration = config
        button.backgroundColor = .secondarySystemBackground
        button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        button.clipsToBounds = true
        button.layer.cornerRadius = 10
        
        return button
    }()
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = .boldSystemFont(ofSize: 18)
        label.textColor = .black
        return label
    }()
    
    let searchKeywordPublisher = PassthroughSubject<String?, Never>()
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
            container.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            container.heightAnchor.constraint(equalToConstant: 44),
        ])
        
        addSubview(searchContainer)
        searchContainer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            searchContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            searchContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            searchContainer.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            searchContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            searchContainer.heightAnchor.constraint(equalToConstant: 44),
        ])
        searchContainer.isHidden = true
    }
    
    func configure(leftViews: [UIView], centerViews: [UIView] = [], rightViews: [UIView]) {
        [leftStack, centerStack, rightStack].forEach { $0.arrangedSubviews.forEach { $0.removeFromSuperview() } }
        
        leftStack.spacing = 20
        rightStack.spacing = 5
        
        leftViews.forEach { leftStack.addArrangedSubview($0) }
        centerViews.forEach { centerStack.addArrangedSubview($0) }
        rightViews.forEach { rightStack.addArrangedSubview($0) }
    }
    
    func configureForRoomCreate(target: AnyObject ,onBack: Selector) {
        titleLabel.text = "방 만들기"
        
        backBtn.removeTarget(nil, action: nil, for: .allEvents)
        backBtn.addTarget(target, action: onBack, for: .touchUpInside)
        
        configure(leftViews: [backBtn], centerViews: [titleLabel], rightViews: [])
    }
    
    func configureForChatRoom(roomTitle: String, participantCount: Int, target: AnyObject ,onBack: Selector, onSearch: Selector, onSetting: Selector) {
        container.isHidden = false
        searchContainer.isHidden = true

        titleLabel.text = roomTitle

        backBtn.removeTarget(nil, action: nil, for: .allEvents)
        searchBtn.removeTarget(nil, action: nil, for: .allEvents)
        settingBtn.removeTarget(nil, action: nil, for: .allEvents)
        
        backBtn.addTarget(target, action: onBack, for: .touchUpInside)
        searchBtn.addTarget(target, action: onSearch, for: .touchUpInside)
        settingBtn.addTarget(target, action: onSetting, for: .touchUpInside)
        
        configure(
            leftViews: [backBtn, titleLabel],
            centerViews: [],
            rightViews: [searchBtn, settingBtn]
        )
    }
    
    func configureForMyPage(target: AnyObject, onSetting: Selector) {
        titleLabel.text = "마이페이지"
        
        
        settingBtn.removeTarget(nil, action: nil, for: .allEvents)
        
        settingBtn.addTarget((target), action: onSetting, for: .touchUpInside)
        
        configure(leftViews: [], centerViews: [titleLabel], rightViews: [settingBtn])
    }
    
    func configureForRoomList(target: AnyObject, onSearch: Selector, onCreate: Selector) {
        titleLabel.text = "OutPick"
        
        searchBtn.removeTarget(nil, action: nil, for: .allEvents)
        createBtn.removeTarget(nil, action: nil, for: .allEvents)
        
        searchBtn.addTarget(target, action: onSearch, for: .touchUpInside)
        createBtn.addTarget(target, action: onCreate, for: .touchUpInside)
        
        configure(
            leftViews: [titleLabel],
            centerViews: [],
            rightViews: [searchBtn, createBtn]
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
        searchTextField.text = nil
        searchTextField.resignFirstResponder()
        container.isHidden = false
        
        cancelSearchPublisher.send()
    }
}

extension UIButton {
    static func navButtonIcon(_ name: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: name)
        config.buttonSize = .small
        config.imagePlacement = .leading
        config.baseForegroundColor = .black

        button.configuration = config
        button.backgroundColor = .secondarySystemBackground
        button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        button.clipsToBounds = true
        button.layer.cornerRadius = 10
        
        return button
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
        searchTextField.resignFirstResponder()
        return true
    }
    
    func textFieldShouldClear(_ textField: UITextField) -> Bool {
        searchKeywordPublisher.send(nil)
        return true
    }
}
