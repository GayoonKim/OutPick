//
//  File.swift
//  OutPick
//
//  Created by 김가윤 on 9/22/25.
//

import UIKit

public final class BannerView: UIView {
    // MARK: - Public
    public enum Style {
        case info
        case error
        case success
        case offline

        var backgroundColor: UIColor {
            switch self {
            case .info: return .secondarySystemBackground
            case .error: return UIColor { trait in trait.userInterfaceStyle == .dark ? UIColor.systemRed.withAlphaComponent(0.35) : UIColor.systemRed.withAlphaComponent(0.12) }
            case .success: return UIColor { trait in trait.userInterfaceStyle == .dark ? UIColor.systemGreen.withAlphaComponent(0.35) : UIColor.systemGreen.withAlphaComponent(0.12) }
            case .offline: return .tertiarySystemBackground
            }
        }
        var accentColor: UIColor {
            switch self {
            case .info: return .systemBlue
            case .error: return .systemRed
            case .success: return .systemGreen
            case .offline: return .systemGray
            }
        }
        var textColor: UIColor { .label }
    }

    public struct Config {
        public var message: String
        public var style: Style
        public var actionTitle: String?
        public var autoHideAfter: TimeInterval?
        public var tapHandler: (() -> Void)?
        public init(message: String, style: Style = .info, actionTitle: String? = nil, autoHideAfter: TimeInterval? = 3.0, tapHandler: (() -> Void)? = nil) {
            self.message = message
            self.style = style
            self.actionTitle = actionTitle
            self.autoHideAfter = autoHideAfter
            self.tapHandler = tapHandler
        }
    }

    // MARK: - Private
    private let accentView = UIView()
    private let label = UILabel()
    private let button = UIButton(type: .system)
    private var tapHandler: (() -> Void)?
    private var hidingWorkItem: DispatchWorkItem?

    // MARK: - Init
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    // MARK: - Setup
    private func setup() {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 12
        layer.masksToBounds = true

        // subtle shadow to lift from background
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.08
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 2)

        accentView.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        button.translatesAutoresizingMaskIntoConstraints = false

        addSubview(accentView)
        addSubview(label)
        addSubview(button)

        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        label.textColor = .label
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true

        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.isHidden = true

        NSLayoutConstraint.activate([
            accentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            accentView.topAnchor.constraint(equalTo: topAnchor),
            accentView.bottomAnchor.constraint(equalTo: bottomAnchor),
            accentView.widthAnchor.constraint(equalToConstant: 4),

            label.leadingAnchor.constraint(equalTo: accentView.trailingAnchor, constant: 12),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

            button.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 8),
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            button.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
        isAccessibilityElement = true
        accessibilityTraits = .staticText
    }

    // MARK: - API
    public func apply(_ config: Config) {
        backgroundColor = config.style.backgroundColor
        accentView.backgroundColor = config.style.accentColor
        label.text = config.message
        label.textColor = config.style.textColor
        accessibilityLabel = config.message

        if let title = config.actionTitle {
            button.setTitle(title, for: .normal)
            button.isHidden = false
            button.removeTarget(nil, action: nil, for: .allEvents)
            button.addAction(UIAction { [weak self] _ in self?.tapHandler?() }, for: .touchUpInside)
            tapHandler = config.tapHandler
        } else {
            button.isHidden = true
            tapHandler = config.tapHandler
        }

        announce(config.message)
        scheduleAutoHide(after: config.autoHideAfter)
    }

    // MARK: - Show helpers
    @discardableResult
    public static func show(on container: UIView,
                            message: String,
                            style: Style = .info,
                            actionTitle: String? = nil,
                            autoHideAfter: TimeInterval? = 3.0,
                            tapHandler: (() -> Void)? = nil) -> BannerView {
        let banner = reuseOrCreate(in: container)
        let config = Config(message: message, style: style, actionTitle: actionTitle, autoHideAfter: autoHideAfter, tapHandler: tapHandler)
        banner.apply(config)
        animateIn(banner)
        return banner
    }

    public func hide(animated: Bool = true) {
        hidingWorkItem?.cancel()
        Self.animateOut(self, animated: animated)
    }

    // MARK: - Weather convenience
    public static func presentWeatherError(on container: UIView, isOffline: Bool) {
        let message = isOffline ? "네트워크 연결을 확인하세요." : "일시적인 오류가 발생했어요. 잠시 후 다시 시도해 주세요."
        let style: Style = isOffline ? .offline : .error
        Self.show(on: container, message: message, style: style, actionTitle: nil, autoHideAfter: 3.0, tapHandler: nil)
    }

    // MARK: - Internals
    private static let tagValue = 246_810 // single instance per container

    private static func reuseOrCreate(in container: UIView) -> BannerView {
        if let existing = container.viewWithTag(tagValue) as? BannerView {
            return existing
        }
        let banner = BannerView()
        banner.tag = tagValue
        banner.alpha = 0
        banner.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(banner)

        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            banner.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            banner.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 8)
        ])
        return banner
    }

    private func scheduleAutoHide(after interval: TimeInterval?) {
        hidingWorkItem?.cancel()
        guard let interval, interval > 0 else { return }
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hidingWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: work)
    }

    @objc private func handleTap() {
        tapHandler?()
    }

    private func announce(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.warning)
    }

    private static func animateIn(_ view: UIView) {
        UIView.animate(withDuration: 0.2) { view.alpha = 1 }
    }
    private static func animateOut(_ view: UIView, animated: Bool = true) {
        let duration = animated ? 0.2 : 0
        UIView.animate(withDuration: duration, animations: { view.alpha = 0 }) { _ in
            // keep for reuse (don’t removeFromSuperview)
        }
    }
}
