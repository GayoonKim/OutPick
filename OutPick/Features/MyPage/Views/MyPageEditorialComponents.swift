import UIKit

enum MyPageEditorialStyle {
    static func serifFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else {
            return base
        }
        return UIFont(descriptor: descriptor, size: size)
    }

    static func configurePrimaryButton(_ button: UIButton, title: String) {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.baseBackgroundColor = OutPickTheme.ColorToken.accent
        configuration.baseForegroundColor = OutPickTheme.ColorToken.backgroundBase
        configuration.cornerStyle = .capsule
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            attributes.font = .systemFont(ofSize: 16, weight: .bold)
            return attributes
        }
        button.configuration = configuration
        button.heightAnchor.constraint(equalToConstant: 54).isActive = true
    }

    static func applyPrimaryButtonState(_ button: UIButton, isEnabled: Bool) {
        button.isEnabled = isEnabled
        button.configuration?.baseBackgroundColor = isEnabled
            ? OutPickTheme.ColorToken.accent
            : OutPickTheme.ColorToken.surfaceElevated
        button.configuration?.baseForegroundColor = isEnabled
            ? OutPickTheme.ColorToken.backgroundBase
            : OutPickTheme.ColorToken.textDisabled
    }
}

final class MyPageEditorialHeaderView: UIView {
    private let eyebrowLabel = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(eyebrow: String, title: String, subtitle: String?) {
        eyebrowLabel.text = eyebrow.uppercased()
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil
    }

    private func configureUI() {
        eyebrowLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        eyebrowLabel.textColor = OutPickTheme.ColorToken.accent
        eyebrowLabel.adjustsFontForContentSizeCategory = true

        titleLabel.font = MyPageEditorialStyle.serifFont(size: 34, weight: .bold)
        titleLabel.textColor = OutPickTheme.ColorToken.textPrimary
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true

        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = OutPickTheme.ColorToken.textSecondary
        subtitleLabel.numberOfLines = 0
        subtitleLabel.adjustsFontForContentSizeCategory = true

        let stack = UIStackView(arrangedSubviews: [eyebrowLabel, titleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.spacing = 8
        stack.setCustomSpacing(12, after: titleLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

final class MyPageMoodChipsView: UIView {
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(names: [String]) {
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let resolvedNames = names.isEmpty ? ["스타일 선택 필요"] : names
        for name in resolvedNames {
            let label = InsetLabel()
            label.text = name
            label.font = .systemFont(ofSize: 13, weight: .semibold)
            label.textColor = names.isEmpty
                ? OutPickTheme.ColorToken.textTertiary
                : OutPickTheme.ColorToken.textPrimary
            label.backgroundColor = .clear
            label.layer.cornerRadius = 16
            label.layer.borderWidth = 1
            label.layer.borderColor = (
                names.isEmpty
                    ? OutPickTheme.ColorToken.borderSubtle
                    : OutPickTheme.ColorToken.borderStrong
            ).cgColor
            label.clipsToBounds = true
            label.accessibilityLabel = name
            stackView.addArrangedSubview(label)
        }
    }

    private func configureUI() {
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.alignment = .center

        [scrollView, stackView].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        addSubview(scrollView)
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 38),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])
    }
}

final class MyPageActionRowButton: UIButton {
    private let actionTitleLabel = UILabel()
    private let actionSubtitleLabel = UILabel()
    private let arrowImageView = UIImageView(image: UIImage(systemName: "arrow.up.right"))
    private let separator = UIView()

    init(title: String, subtitle: String) {
        super.init(frame: .zero)
        configureUI()
        actionTitleLabel.text = title
        actionSubtitleLabel.text = subtitle
        accessibilityLabel = "\(title), \(subtitle)"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.12) {
                self.alpha = self.isHighlighted ? 0.55 : 1
                self.transform = self.isHighlighted
                    ? CGAffineTransform(translationX: 3, y: 0)
                    : .identity
            }
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isHidden == false,
              alpha > 0.01,
              isUserInteractionEnabled,
              self.point(inside: point, with: event) else {
            return nil
        }
        return self
    }

    private func configureUI() {
        actionTitleLabel.font = MyPageEditorialStyle.serifFont(size: 21, weight: .semibold)
        actionTitleLabel.textColor = OutPickTheme.ColorToken.textPrimary
        actionTitleLabel.adjustsFontForContentSizeCategory = true

        actionSubtitleLabel.font = .preferredFont(forTextStyle: .caption1)
        actionSubtitleLabel.textColor = OutPickTheme.ColorToken.textSecondary
        actionSubtitleLabel.adjustsFontForContentSizeCategory = true

        arrowImageView.tintColor = OutPickTheme.ColorToken.accent
        arrowImageView.contentMode = .scaleAspectFit
        arrowImageView.setContentHuggingPriority(.required, for: .horizontal)
        separator.backgroundColor = OutPickTheme.ColorToken.borderSubtle

        let labels = UIStackView(arrangedSubviews: [actionTitleLabel, actionSubtitleLabel])
        labels.axis = .vertical
        labels.spacing = 5

        let row = UIStackView(arrangedSubviews: [labels, arrowImageView])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 16
        row.isUserInteractionEnabled = false
        separator.isUserInteractionEnabled = false

        [row, separator].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.bottomAnchor.constraint(equalTo: separator.topAnchor, constant: -18),
            arrowImageView.widthAnchor.constraint(equalToConstant: 18),
            arrowImageView.heightAnchor.constraint(equalToConstant: 18),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
        ])
    }
}

private final class InsetLabel: UILabel {
    private let insets = UIEdgeInsets(top: 7, left: 14, bottom: 7, right: 14)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + insets.left + insets.right,
            height: size.height + insets.top + insets.bottom
        )
    }
}
