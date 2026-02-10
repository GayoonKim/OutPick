//
//  EditRoomDesTableViewCell.swift
//  OutPick
//
//  Created by 김가윤 on 6/24/25.
//

import UIKit
import Combine

// 방 설명 셀
class EditRoomDesTableViewCell: UITableViewCell {
    static let identifier = "EditRoomDesCell"
    
    private let defaultText = "• 어떤 사람이 참여하면 좋을까요?\n• 지켜야 할 규칙, 공지 사항 등을 안내해 주세요."
    
    private let desTextView: UITextView = {
        let textView = UITextView()
        textView.textColor = .placeholderText
        textView.text = "• 어떤 사람이 참여하면 좋을까요?\n• 지켜야 할 규칙, 공지 사항 등을 안내해 주세요."
        textView.font = UIFont.systemFont(ofSize: 14)
        textView.isScrollEnabled = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.textContainer.lineFragmentPadding = 0
        textView.backgroundColor = .secondarySystemBackground
        
        return textView
    }()
    
    private let desCountLabel: UILabel = {
        let label = UILabel()
        label.text = "0/200"
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        label.backgroundColor = .secondarySystemBackground

        return label
    }()
    
    private var tableView: UITableView? {
        var view = superview
        while view != nil && !(view is UITableView) {
            view = view?.superview
        }
        return view as? UITableView
    }
    
    private let maxLength = 200
    private let maxHeight: CGFloat = 200
    private var fixedHeightConstraint: NSLayoutConstraint?
    
    let textViewChanged = PassthroughSubject<(CGRect, String), Never>()

    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        selectionStyle = .none
        setupViews()
    }
    
    private func setupViews() {
        desTextView.delegate = self
        
        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = 10
        
        contentView.addSubview(desTextView)
        contentView.addSubview(desCountLabel)

        NSLayoutConstraint.activate([
            desTextView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            desTextView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            desTextView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),
            desTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 100),
            desTextView.bottomAnchor.constraint(equalTo: desCountLabel.topAnchor, constant: -5),
            
            desCountLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            desCountLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
    }
    
    func configure(_ room: ChatRoom) {
        self.desTextView.text = room.roomDescription
        self.desTextView.textColor = .black
        self.desCountLabel.text = "\(room.roomDescription.count)/\(maxLength)"
    }
    
    @MainActor
    private func updateNameCountLabel() {
        guard let text = desTextView.text,
              text != defaultText else {
            desCountLabel.text = "0/\(maxLength)"
            return
        }

        if text.count > maxLength {
            let limited = String(text.prefix(maxLength))
            desTextView.text = limited
            desCountLabel.text = "\(limited.count)/\(maxLength)"
        } else {
            desCountLabel.text = "\(text.count)/\(maxLength)"
        }

    }

    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        return false
    }
}

extension EditRoomDesTableViewCell: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        let size = textView.sizeThatFits(CGSize(width: textView.frame.width, height: CGFloat.greatestFiniteMagnitude))
        
        if size.height >= maxHeight {
            if self.fixedHeightConstraint == nil {
                self.fixedHeightConstraint = textView.heightAnchor.constraint(equalToConstant: maxHeight)
                self.fixedHeightConstraint?.isActive = true
            }
            textView.isScrollEnabled = true
        } else {
            self.fixedHeightConstraint?.isActive = false
            self.fixedHeightConstraint = nil
            
            textView.isScrollEnabled = false
            desTextView.invalidateIntrinsicContentSize()
        }
        
        if let tableView = self.tableView {
            tableView.beginUpdates()
            tableView.endUpdates()
        }
        
        self.updateNameCountLabel()
        
        let convertedRect = textView.convert(textView.bounds, to: tableView)
        textViewChanged.send((convertedRect, textView.text))
    }
    
    func textViewDidBeginEditing(_ textView: UITextView) {
        if textView.textColor == .placeholderText {
            textView.text = nil
            textView.textColor = .black
        }
        
        self.updateNameCountLabel()
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        if textView.text.isEmpty {
            textView.text = defaultText
            textView.textColor = .placeholderText
        }
        
        self.updateNameCountLabel()
        
    }
}
