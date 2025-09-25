//
//  AnnouncementBannerView.swift
//  OutPick
//
//  Created by 김가윤 on 9/25/25.
//

import Foundation
import UIKit

// MARK: - AnnouncementBannerView
final class AnnouncementBannerView: UIView {
    // Public callbacks
    var onPinToggle: ((Bool) -> Void)?
    var onExpandToggle: ((Bool) -> Void)?
    var onHeightChange: (() -> Void)?

    // State
    private(set) var isPinned: Bool = true
    private(set) var isExpanded: Bool = false {
        didSet { applyExpandedState(animated: true) }
    }

    // Layout tuning
    private let collapsedSpacing: CGFloat = 6
    private let expandedSpacing: CGFloat = 10

    // UI
    private let container = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let iconView = UIImageView(image: UIImage(systemName: "megaphone.fill"))
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let metaLabel = UILabel()
    private let pinButton = UIButton(type: .system)
    private let expandButton = UIButton(type: .system)
    private let vStack = UIStackView()
    private let headerHStack = UIStackView()
    private let footerHStack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        backgroundColor = .clear
        translatesAutoresizingMaskIntoConstraints = false

        container.translatesAutoresizingMaskIntoConstraints = false
        container.clipsToBounds = true
        container.layer.cornerRadius = 14

        addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])

        // Header
        iconView.tintColor = .label
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 18).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 18).isActive = true

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.text = "공지"

        pinButton.setImage(UIImage(systemName: "pin.fill"), for: .normal)
        pinButton.tintColor = .secondaryLabel
        pinButton.addTarget(self, action: #selector(didTapPin), for: .touchUpInside)
        pinButton.setContentHuggingPriority(.required, for: .horizontal)

        expandButton.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        expandButton.tintColor = .secondaryLabel
        expandButton.addTarget(self, action: #selector(didTapExpand), for: .touchUpInside)
        expandButton.setContentHuggingPriority(.required, for: .horizontal)

        headerHStack.axis = .horizontal
        headerHStack.alignment = .center
        headerHStack.spacing = 8
        headerHStack.addArrangedSubview(iconView)
        headerHStack.addArrangedSubview(titleLabel)
        headerHStack.addArrangedSubview(UIView())
//        headerHStack.addArrangedSubview(pinButton)
        headerHStack.addArrangedSubview(expandButton)

        // Message
        messageLabel.numberOfLines = 1
        messageLabel.font = .systemFont(ofSize: 14)
        messageLabel.textColor = .label
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.setContentHuggingPriority(.defaultLow, for: .vertical)
        messageLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        // Footer
        metaLabel.font = .systemFont(ofSize: 12)
        metaLabel.textColor = .secondaryLabel


        footerHStack.axis = .horizontal
        footerHStack.alignment = .center
        footerHStack.spacing = 8
        footerHStack.addArrangedSubview(metaLabel)
        footerHStack.addArrangedSubview(UIView())
        footerHStack.isHidden = true // start collapsed

        // Main stack
        vStack.axis = .vertical
        vStack.spacing = collapsedSpacing
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.addArrangedSubview(headerHStack)
        vStack.addArrangedSubview(messageLabel)
        vStack.addArrangedSubview(footerHStack)

        container.contentView.addSubview(vStack)
        NSLayoutConstraint.activate([
            vStack.topAnchor.constraint(equalTo: container.contentView.topAnchor, constant: 10),
            vStack.leadingAnchor.constraint(equalTo: container.contentView.leadingAnchor, constant: 12),
            vStack.trailingAnchor.constraint(equalTo: container.contentView.trailingAnchor, constant: -12),
            vStack.bottomAnchor.constraint(equalTo: container.contentView.bottomAnchor, constant: -10)
        ])

        // Tap to expand/collapse
        let tap = UITapGestureRecognizer(target: self, action: #selector(didTapExpand))
        container.addGestureRecognizer(tap)

        // Initial state
        applyExpandedState(animated: false)
    }

    /// Configure banner content
    func configure(text: String, authorID: String, createdAt: Date, pinned: Bool) {
        messageLabel.text = text
        metaLabel.text = "작성자: \(authorID) · \(relativeDate(from: createdAt))"

        setPinned(pinned)
        setNeedsLayout()
        layoutIfNeeded()
        onHeightChange?()
    }

    func setPinned(_ pinned: Bool) {
        isPinned = pinned
        let name = pinned ? "pin.fill" : "pin.slash"
        pinButton.setImage(UIImage(systemName: name), for: .normal)
    }

    func setExpanded(_ expanded: Bool, animated: Bool) {
        isExpanded = expanded
        applyExpandedState(animated: animated)
    }

    @objc private func didTapPin() {
        setPinned(!isPinned)
        onPinToggle?(isPinned)
    }

    @objc private func didTapExpand() {
        if #available(iOS 10.0, *) { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        setExpanded(!isExpanded, animated: true)
        onExpandToggle?(isExpanded)
    }

    private func applyExpandedState(animated: Bool) {
        let changes = {
            self.messageLabel.numberOfLines = self.isExpanded ? 0 : 1
            self.expandButton.setImage(UIImage(systemName: self.isExpanded ? "chevron.up" : "chevron.down"), for: .normal)
            self.expandButton.accessibilityValue = self.isExpanded ? "펼침" : "접힘"
            self.footerHStack.isHidden = !self.isExpanded
            self.vStack.spacing = self.isExpanded ? self.expandedSpacing : self.collapsedSpacing
            self.setNeedsLayout()
            self.layoutIfNeeded()
            self.superview?.setNeedsLayout()
            self.superview?.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.22, animations: changes, completion: { _ in
                self.onHeightChange?()
            })
        } else {
            changes()
            self.onHeightChange?()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Ensure multiline label computes correct height for current width
        messageLabel.preferredMaxLayoutWidth = vStack.bounds.width
    }

    private func relativeDate(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "방금" }
        let mins = Int(interval/60)
        if mins < 60 { return "\(mins)분 전" }
        let hours = mins/60
        if hours < 24 { return "\(hours)시간 전" }
        let days = hours/24
        return "\(days)일 전"
    }

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy.MM.dd HH:mm"
        return f.string(from: date)
    }
}
