//
//  BottomActionSheetView.swift
//  OutPick
//
//  Created by Codex on 3/27/26.
//

import UIKit

final class BottomActionSheetView: UIView {
    struct Action {
        enum Style {
            case normal
            case destructive
            case cancel
        }

        let title: String
        let style: Style
        let handler: (() -> Void)?

        init(title: String, style: Style = .normal, handler: (() -> Void)? = nil) {
            self.title = title
            self.style = style
            self.handler = handler
        }
    }

    var onDismiss: (() -> Void)?

    private let sheetContainer = UIView()
    private let contentStack = UIStackView()
    private let actionsCard = UIStackView()
    private let cancelCard = UIStackView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let titleMessageStack = UIStackView()
    private let actions: [Action]
    private var isDismissing = false

    init(title: String?, message: String?, actions: [Action]) {
        self.actions = actions
        super.init(frame: .zero)
        setupUI(title: title, message: message)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @discardableResult
    static func present(
        in parent: UIView,
        title: String? = nil,
        message: String? = nil,
        actions: [Action]
    ) -> BottomActionSheetView {
        let view = BottomActionSheetView(title: title, message: message, actions: actions)
        view.show(in: parent)
        return view
    }

    func dismiss(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard !isDismissing else { return }
        isDismissing = true

        let animations = {
            self.alpha = 0
            self.sheetContainer.transform = CGAffineTransform(translationX: 0, y: 24)
        }
        let end: (Bool) -> Void = { _ in
            self.removeFromSuperview()
            self.onDismiss?()
            completion?()
        }

        if animated {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseIn], animations: animations, completion: end)
        } else {
            animations()
            end(true)
        }
    }

    private func show(in parent: UIView) {
        translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(self)

        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: parent.topAnchor),
            leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            bottomAnchor.constraint(equalTo: parent.bottomAnchor)
        ])

        alpha = 0
        sheetContainer.transform = CGAffineTransform(translationX: 0, y: 24)

        UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseOut]) {
            self.alpha = 1
            self.sheetContainer.transform = .identity
        }
    }

    private func setupUI(title: String?, message: String?) {
        backgroundColor = UIColor.black.withAlphaComponent(0.24)

        let dismissTap = UITapGestureRecognizer(target: self, action: #selector(dimmedBackgroundTapped))
        dismissTap.cancelsTouchesInView = false
        addGestureRecognizer(dismissTap)

        sheetContainer.translatesAutoresizingMaskIntoConstraints = false
        sheetContainer.backgroundColor = .clear
        addSubview(sheetContainer)

        NSLayoutConstraint.activate([
            sheetContainer.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 12),
            sheetContainer.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -12),
            sheetContainer.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -8)
        ])

        contentStack.axis = .vertical
        contentStack.spacing = 10
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        sheetContainer.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: sheetContainer.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: sheetContainer.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: sheetContainer.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: sheetContainer.bottomAnchor)
        ])

        let regularActions = actions.enumerated().filter { $0.element.style != .cancel }
        let cancelAction = actions.enumerated().first(where: { $0.element.style == .cancel })

        actionsCard.axis = .vertical
        actionsCard.spacing = 0
        actionsCard.backgroundColor = .secondarySystemBackground
        actionsCard.layer.cornerRadius = 18
        actionsCard.clipsToBounds = true
        contentStack.addArrangedSubview(actionsCard)

        titleMessageStack.axis = .vertical
        titleMessageStack.spacing = 6
        titleMessageStack.isLayoutMarginsRelativeArrangement = true
        titleMessageStack.layoutMargins = UIEdgeInsets(top: 16, left: 20, bottom: 14, right: 20)

        if let title, !title.isEmpty {
            titleLabel.text = title
            titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
            titleLabel.textColor = .secondaryLabel
            titleLabel.textAlignment = .center
            titleLabel.numberOfLines = 0
            titleMessageStack.addArrangedSubview(titleLabel)
        }

        if let message, !message.isEmpty {
            messageLabel.text = message
            messageLabel.font = .systemFont(ofSize: 13)
            messageLabel.textColor = .secondaryLabel
            messageLabel.textAlignment = .center
            messageLabel.numberOfLines = 0
            titleMessageStack.addArrangedSubview(messageLabel)
        }

        if !titleMessageStack.arrangedSubviews.isEmpty {
            actionsCard.addArrangedSubview(titleMessageStack)
            actionsCard.addArrangedSubview(makeSeparator())
        }

        for (position, actionEntry) in regularActions.enumerated() {
            let button = makeButton(for: actionEntry.element, index: actionEntry.offset)
            actionsCard.addArrangedSubview(button)
            if position < regularActions.count - 1 {
                actionsCard.addArrangedSubview(makeSeparator())
            }
        }

        if let cancelAction {
            cancelCard.axis = .vertical
            cancelCard.backgroundColor = .secondarySystemBackground
            cancelCard.layer.cornerRadius = 18
            cancelCard.clipsToBounds = true
            let button = makeButton(for: cancelAction.element, index: cancelAction.offset)
            cancelCard.addArrangedSubview(button)
            contentStack.addArrangedSubview(cancelCard)
        }
    }

    private func makeButton(for action: Action, index: Int) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        configuration.baseForegroundColor = foregroundColor(for: action.style)
        configuration.title = action.title
        configuration.titleAlignment = .center

        let button = UIButton(configuration: configuration)
        button.tag = index
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: action.style == .cancel ? .semibold : .regular)
        button.addTarget(self, action: #selector(actionButtonTapped(_:)), for: .touchUpInside)
        return button
    }

    private func foregroundColor(for style: Action.Style) -> UIColor {
        switch style {
        case .normal, .cancel:
            return .label
        case .destructive:
            return .systemRed
        }
    }

    private func makeSeparator() -> UIView {
        let separator = UIView()
        separator.backgroundColor = UIColor.separator.withAlphaComponent(0.5)
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        return separator
    }

    @objc
    private func dimmedBackgroundTapped(_ gestureRecognizer: UITapGestureRecognizer) {
        let location = gestureRecognizer.location(in: self)
        guard !sheetContainer.frame.contains(location) else { return }
        dismiss()
    }

    @objc
    private func actionButtonTapped(_ sender: UIButton) {
        let action = actions[sender.tag]
        dismiss { [handler = action.handler] in
            handler?()
        }
    }
}
