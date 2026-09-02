//
//  RoomRoleEventCollectionViewCell.swift
//  OutPick
//
//  Created by Codex on 9/1/26.
//

import UIKit

final class RoomRoleEventCollectionViewCell: UICollectionViewCell {
    static let reuseIdentifier = "RoomRoleEventCollectionViewCell"

    private let containerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = OutPickTheme.ColorToken.surfaceBase
        view.layer.cornerRadius = 12
        return view
    }()

    private let eventLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = OutPickTheme.ColorToken.textSecondary
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(containerView)
        containerView.addSubview(eventLabel)

        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),
            containerView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 28),
            containerView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -28),

            eventLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            eventLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            eventLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 7),
            eventLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -7)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        eventLabel.text = nil
        accessibilityLabel = nil
    }

    func configure(with payload: RoomRoleEventPayload) {
        eventLabel.text = payload.displayText
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        accessibilityLabel = payload.displayText
    }
}
