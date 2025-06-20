//
//  EditRoomNameTableViewCell.swift
//  OutPick
//
//  Created by 김가윤 on 6/20/25.
//

import UIKit

class EditRoomNameTableViewCell: UITableViewCell {
    static let identifier = "EditRoomNameCell"

//    private let nameTextField: UITextField = {
//        let textField = UITextField()
//        textField.placeholder = "채팅방 이름 (필수)"
//        textField.borderStyle = .roundedRect
//        textField.returnKeyType = .done
//        textField.clearButtonMode = .whileEditing
//        textField.translatesAutoresizingMaskIntoConstraints = false
//
//        return textField
//    }()
    
    private let nameTextView: UITextView = {
        let textView = UITextView()
        textView.text = "채팅방 이름 (필수)"
        textView.textColor = .lightGray
        textView.font = UIFont.systemFont(ofSize: 18)
        textView.isScrollEnabled = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.textContainer.lineFragmentPadding = 0
        
        return textView
    }()

    private let nameCountLabel: UILabel = {
        let label = UILabel()
        label.text = "0/20"
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false

        return label
    }()
    
    private let clearButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        button.tintColor = .secondaryLabel
        button.isHidden = true
        button.translatesAutoresizingMaskIntoConstraints = false
        
        return button
    }()

    private let horizontalStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false

        return stackView
    }()
    
    private var tableView: UITableView? {
        var view = superview
        while view != nil && !(view is UITableView) {
            view = view?.superview
        }
        return view as? UITableView
    }

    private let maxLength = 20
    private(set) var minHeight: CGFloat = 50
    private(set) var maxHeight: CGFloat = 120
    private var nameTextViewHeightConstraint: NSLayoutConstraint!

    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        nameTextView.delegate = self
        clearButton.addTarget(self, action: #selector(clearButtonTapped), for: .touchUpInside)

        contentView.addSubview(nameTextView)
        contentView.addSubview(clearButton)
        contentView.addSubview(nameCountLabel)

        nameTextView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameTextView.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        clearButton.setContentHuggingPriority(.required, for: .horizontal)
        clearButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        nameCountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([

            nameCountLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            nameCountLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
        
            clearButton.trailingAnchor.constraint(equalTo: nameCountLabel.leadingAnchor, constant: -8),
            clearButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            
            nameTextView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            nameTextView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            nameTextView.widthAnchor.constraint(equalToConstant: contentView.bounds.width - (clearButton.frame.width + 8 + 8) - (nameCountLabel.frame.width + 8) - 16),
        ])

        nameTextViewHeightConstraint = nameTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 40)
        nameTextViewHeightConstraint.priority = .defaultHigh
        nameTextViewHeightConstraint.isActive = true
    }
    
    @MainActor
    @objc private func clearButtonTapped() {
        nameTextView.text = ""
        nameTextView.textColor = .lightGray
        
        updateNameCountLabel()
        clearButton.isHidden = true
        nameTextView.resignFirstResponder()
        invalidateIntrinsicContentSize()
    }

    @MainActor
    private func updateNameCountLabel() {
        guard let text = nameTextView.text,
              text != "채팅방 이름 (필수)" else {
            nameCountLabel.text = "0/\(maxLength)"
            return
        }

        if text.count > maxLength {
            let limited = String(text.prefix(maxLength))
            nameTextView.text = limited
            nameCountLabel.text = "\(limited.count)/\(maxLength)"
        } else {
            nameCountLabel.text = "\(text.count)/\(maxLength)"
        }

    }
}

extension EditRoomNameTableViewCell: UITextViewDelegate {
    @MainActor
    func textViewDidChange(_ textView: UITextView) {
        
        DispatchQueue.main.async {
            if self.nameTextView.text.isEmpty {
                self.clearButton.isHidden = true
            } else {
                self.clearButton.isHidden = false
            }
            
            self.updateNameCountLabel()
        }
        
    }
    
    @MainActor
    func textViewDidBeginEditing(_ textView: UITextView) {
        DispatchQueue.main.async {
            if self.nameTextView.textColor == .lightGray {
                self.nameTextView.text = ""
                self.nameTextView.textColor = .black
            }
            
            self.updateNameCountLabel()
        }
        
    }
    
    @MainActor
    func textViewDidEndEditing(_ textView: UITextView) {
        DispatchQueue.main.async {
            if self.nameTextView.text.isEmpty {
                self.nameTextView.text = "채팅방 이름 (필수)"
                self.nameTextView.textColor = .lightGray
            }
            
            self.updateNameCountLabel()
        }
    }
    
    @MainActor
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            textView.resignFirstResponder()
            self.clearButton.isHidden = true
            return false
        }
        
        return true
    }
}
