//
//  EditRoomNameTableViewCell.swift
//  OutPick
//
//  Created by 김가윤 on 6/20/25.
//

import UIKit

class EditRoomNameTableViewCell: UITableViewCell, UITextFieldDelegate {
    static let identifier = "EditRoomNameCell"

    private let nameTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "채팅방 이름 (필수)"
        textField.borderStyle = .roundedRect
        textField.returnKeyType = .done
        textField.clearButtonMode = .whileEditing
        textField.translatesAutoresizingMaskIntoConstraints = false

        return textField
    }()

    private let nameCountLabel: UILabel = {
        let label = UILabel()
        label.text = "0/20"
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false

        return label
    }()

    private let horizontalStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false

        return stackView
    }()

    private let maxLength = 20

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
        nameTextField.delegate = self
        nameTextField.addTarget(self, action: #selector(updateNameCountLabel), for: .editingChanged)

        horizontalStackView.addArrangedSubview(nameTextField)
        horizontalStackView.addArrangedSubview(nameCountLabel)

        nameTextField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameTextField.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        nameCountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        contentView.addSubview(horizontalStackView)
        NSLayoutConstraint.activate([
            horizontalStackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            horizontalStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            horizontalStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            horizontalStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    @objc private func updateNameCountLabel() {
        guard let text = nameTextField.text else { return }

        if text.count > maxLength {
            let limited = String(text.prefix(maxLength))
            nameTextField.text = limited
            nameCountLabel.text = "\(limited.count)/\(maxLength)"
        } else {
            nameCountLabel.text = "\(text.count)/\(maxLength)"
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

}
