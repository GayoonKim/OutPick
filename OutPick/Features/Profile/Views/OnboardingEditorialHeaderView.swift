import UIKit

final class OnboardingEditorialHeaderView: UIView {
    private let stepLabel = UILabel()
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

    func configure(step: String, title: String, subtitle: String) {
        stepLabel.text = step
        stepLabel.accessibilityLabel = "온보딩 \(step)"
        titleLabel.text = title
        subtitleLabel.text = subtitle
    }

    private func configureUI() {
        stepLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        stepLabel.textColor = OutPickTheme.ColorToken.accent

        let descriptor = UIFont.systemFont(ofSize: 34, weight: .bold)
            .fontDescriptor
            .withDesign(.serif)
        titleLabel.font = descriptor.map { UIFont(descriptor: $0, size: 34) }
            ?? .systemFont(ofSize: 34, weight: .bold)
        titleLabel.textColor = OutPickTheme.ColorToken.textPrimary
        titleLabel.numberOfLines = 0

        subtitleLabel.font = .systemFont(ofSize: 15, weight: .regular)
        subtitleLabel.textColor = OutPickTheme.ColorToken.textSecondary
        subtitleLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [stepLabel, titleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.spacing = 10
        stack.setCustomSpacing(14, after: titleLabel)
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
