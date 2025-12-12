//
//  EditRoomNameTableViewCell.swift
//  OutPick
//
//  Created by 김가윤 on 6/20/25.
//

import UIKit
import Combine

class EditRoomNameTableViewCell: UITableViewCell {
    static let identifier = "EditRoomNameCell"
    
    let nameTextChanged = PassthroughSubject<String, Never>()

    private let nameTextView: UITextView = {
        let textView = UITextView()
        textView.textColor = .placeholderText
        textView.text = "채팅방 이름 (필수)"
        textView.font = UIFont.systemFont(ofSize: 14)
        textView.isScrollEnabled = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.textContainer.lineFragmentPadding = 0
        textView.backgroundColor = .secondarySystemBackground
        
        return textView
    }()

    private let nameCountLabel: UILabel = {
        let label = UILabel()
        label.text = "0/20"
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        label.backgroundColor = .secondarySystemBackground

        return label
    }()
    
    private let clearButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        button.tintColor = .secondaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        
        return button
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
        selectionStyle = .none
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        nameTextView.delegate = self
        clearButton.addTarget(self, action: #selector(clearButtonTapped), for: .touchUpInside)

        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = 10
        
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
        
            clearButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            clearButton.heightAnchor.constraint(equalToConstant: 15),
            clearButton.widthAnchor.constraint(equalToConstant: 15),

            nameTextView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 3),
            nameTextView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3),
            nameTextView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            nameTextView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            nameTextView.widthAnchor.constraint(equalToConstant: contentView.frame.width - clearButton.frame.width - nameCountLabel.frame.width - 46),
            nameTextView.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -3),
        ])
    }
    
    func configure(_ room: ChatRoom) {
        self.nameTextView.text = room.roomName
        self.nameTextView.textColor = .black
        self.nameCountLabel.text = "\(room.roomName.count)/\(maxLength)"
    }
    
    @MainActor
    @objc private func clearButtonTapped() {
        nameTextView.text = "채팅방 이름 (필수)"
        nameTextView.textColor = .placeholderText
        nameTextChanged.send(nameTextView.text ?? "")
        
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
    
    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        return false
    }
}

extension EditRoomNameTableViewCell: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        DispatchQueue.main.async {
            if self.nameTextView.text.isEmpty {
                self.clearButton.isHidden = true
            } else {
                self.clearButton.isHidden = false
            }
            
            if let tableView = self.tableView {
                tableView.beginUpdates()
                tableView.endUpdates()
            }
    
            self.updateNameCountLabel()
            self.nameTextChanged.send(textView.text)
        }
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        DispatchQueue.main.async {
            print(textView.layer.bounds.maxY)
            
            if textView.textColor == .placeholderText {
                textView.text = nil
                textView.textColor = .black
            }
            
            self.updateNameCountLabel()
        }
        
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        DispatchQueue.main.async {
            if textView.text.isEmpty {
                textView.text = "채팅방 이름 (필수)"
                textView.textColor = .placeholderText
            }
            
            self.updateNameCountLabel()
        }
    }
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            textView.resignFirstResponder()
            self.clearButton.isHidden = true
            return false
        }
        
        return true
    }
}

extension UIView {
    func superview<T: UIView>(of type: T.Type) -> T? {
        var view = self.superview
        
        while let current = view {
            if let match = current as? T {
                return match
            }
            
            view = current.superview
        }
        
        return nil
    }
}
