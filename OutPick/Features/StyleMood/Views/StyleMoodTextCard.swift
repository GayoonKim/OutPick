import UIKit

final class StyleMoodTextCard: UICollectionViewCell {
    static let reuseIdentifier = "StyleMoodTextCard"

    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 10
        contentView.layer.borderWidth = 1

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
        apply(isSelected: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, isSelected: Bool) {
        titleLabel.text = title
        accessibilityLabel = title
        accessibilityTraits = isSelected ? [.button, .selected] : [.button]
        apply(isSelected: isSelected)
    }

    func animateSelectionFeedback() {
        guard UIAccessibility.isReduceMotionEnabled == false else { return }
        UIView.animate(
            withDuration: 0.1,
            animations: {
                self.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
            },
            completion: { _ in
                UIView.animate(withDuration: 0.18) {
                    self.transform = .identity
                }
            }
        )
    }

    private func apply(isSelected: Bool) {
        contentView.backgroundColor = isSelected
            ? OutPickTheme.ColorToken.accent
            : OutPickTheme.ColorToken.surfaceBase
        contentView.layer.borderColor = (
            isSelected
                ? OutPickTheme.ColorToken.accent
                : OutPickTheme.ColorToken.borderSubtle
        ).cgColor
        titleLabel.textColor = isSelected
            ? OutPickTheme.ColorToken.backgroundBase
            : OutPickTheme.ColorToken.textPrimary
    }
}
