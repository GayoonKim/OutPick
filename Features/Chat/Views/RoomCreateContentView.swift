//
//  RoomCreateContentView.swift
//  OutPick
//
//  Created by Codex on 2/25/26.
//

import UIKit

final class RoomCreateContentView: UIView {
    let scrollView = UIScrollView()
    let roomImageView = UIImageView()
    let roomNameTextView = UITextView()
    let roomNameCountLabel = UILabel()
    let roomDescriptionTextView = UITextView()
    let roomDescriptionCountLabel = UILabel()
    let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let contentContainer = UIView()
    private let roomNameTitleLabel = UILabel()
    private let roomDescriptionTitleLabel = UILabel()
    private(set) var scrollViewTopConstraint: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureHierarchy()
        configureStyles()
        configureLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("Use programmatic init for RoomCreateContentView.")
    }

    private func configureHierarchy() {
        addSubview(scrollView)
        addSubview(activityIndicator)
        scrollView.addSubview(contentContainer)

        [
            roomImageView,
            roomNameTitleLabel,
            roomNameTextView,
            roomNameCountLabel,
            roomDescriptionTitleLabel,
            roomDescriptionTextView,
            roomDescriptionCountLabel
        ].forEach { contentContainer.addSubview($0) }
    }

    private func configureStyles() {
        backgroundColor = .systemBackground

        [
            scrollView,
            contentContainer,
            roomImageView,
            roomNameTextView,
            roomNameCountLabel,
            roomDescriptionTextView,
            roomDescriptionCountLabel,
            activityIndicator,
            roomNameTitleLabel,
            roomDescriptionTitleLabel
        ].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        roomImageView.image = UIImage(named: "Default_Profile")
        roomImageView.contentMode = .scaleAspectFill
        roomImageView.backgroundColor = UIColor(white: 0.95, alpha: 1.0)

        roomNameTitleLabel.text = "방 이름"
        roomDescriptionTitleLabel.text = "방 설명"
        [roomNameTitleLabel, roomDescriptionTitleLabel].forEach {
            $0.font = .systemFont(ofSize: 13, weight: .semibold)
            $0.textColor = .secondaryLabel
        }

        roomNameCountLabel.text = "0 / 20"
        roomDescriptionCountLabel.text = "0 / 200"
        [roomNameCountLabel, roomDescriptionCountLabel].forEach {
            $0.font = .systemFont(ofSize: 12, weight: .regular)
            $0.textColor = .secondaryLabel
            $0.textAlignment = .right
        }

        roomNameTextView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        roomDescriptionTextView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        roomNameTextView.isScrollEnabled = false
        roomDescriptionTextView.isScrollEnabled = true
    }

    private func configureLayout() {
        scrollViewTopConstraint = scrollView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor)

        NSLayoutConstraint.activate([
            scrollViewTopConstraint,
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentContainer.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentContainer.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            roomImageView.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: 20),
            roomImageView.centerXAnchor.constraint(equalTo: contentContainer.centerXAnchor),
            roomImageView.widthAnchor.constraint(equalToConstant: 120),
            roomImageView.heightAnchor.constraint(equalToConstant: 120),

            roomNameTitleLabel.topAnchor.constraint(equalTo: roomImageView.bottomAnchor, constant: 24),
            roomNameTitleLabel.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 20),
            roomNameTitleLabel.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -20),

            roomNameTextView.topAnchor.constraint(equalTo: roomNameTitleLabel.bottomAnchor, constant: 8),
            roomNameTextView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 20),
            roomNameTextView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -20),
            roomNameTextView.heightAnchor.constraint(equalToConstant: 48),

            roomNameCountLabel.topAnchor.constraint(equalTo: roomNameTextView.bottomAnchor, constant: 6),
            roomNameCountLabel.trailingAnchor.constraint(equalTo: roomNameTextView.trailingAnchor),

            roomDescriptionTitleLabel.topAnchor.constraint(equalTo: roomNameCountLabel.bottomAnchor, constant: 16),
            roomDescriptionTitleLabel.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 20),
            roomDescriptionTitleLabel.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -20),

            roomDescriptionTextView.topAnchor.constraint(equalTo: roomDescriptionTitleLabel.bottomAnchor, constant: 8),
            roomDescriptionTextView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 20),
            roomDescriptionTextView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -20),
            roomDescriptionTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 140),

            roomDescriptionCountLabel.topAnchor.constraint(equalTo: roomDescriptionTextView.bottomAnchor, constant: 6),
            roomDescriptionCountLabel.trailingAnchor.constraint(equalTo: roomDescriptionTextView.trailingAnchor),
            roomDescriptionCountLabel.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor, constant: -100),

            activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

