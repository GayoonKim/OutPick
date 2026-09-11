import UIKit

final class ImageViewerChromeView: UIView {
    let closeButton = UIButton(type: .system)
    let saveButton = UIButton(type: .system)
    let reportButton = UIButton(type: .system)
    private let counter = UILabel()
    private let top = UIView()
    private let bottom = UIView()
    private let topGradient = CAGradientLayer()
    private let bottomGradient = CAGradientLayer()

    init(hasReport: Bool) {
        super.init(frame: .zero)
        for bar in [top, bottom] {
            bar.translatesAutoresizingMaskIntoConstraints = false
            addSubview(bar)
        }
        top.layer.insertSublayer(topGradient, at: 0)
        bottom.layer.insertSublayer(bottomGradient, at: 0)
        let shade = OutPickTheme.ColorToken.backgroundBase.withAlphaComponent(0.9).cgColor
        topGradient.colors = [shade, UIColor.clear.cgColor]
        bottomGradient.colors = [UIColor.clear.cgColor, shade]
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.accessibilityLabel = "닫기"
        saveButton.setImage(UIImage(systemName: "arrow.down.to.line"), for: .normal)
        saveButton.setTitle(" 저장", for: .normal)
        reportButton.setTitle("신고", for: .normal)
        reportButton.isHidden = !hasReport
        counter.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .monospacedSystemFont(ofSize: 12, weight: .medium))
        counter.adjustsFontForContentSizeCategory = true
        counter.textColor = OutPickTheme.ColorToken.textSecondary
        counter.textAlignment = .center
        counter.setContentCompressionResistancePriority(.required, for: .horizontal)
        for button in [closeButton, saveButton, reportButton] {
            button.tintColor = OutPickTheme.ColorToken.textPrimary
            button.setTitleColor(OutPickTheme.ColorToken.textPrimary, for: .normal)
            button.setTitleColor(OutPickTheme.ColorToken.textSecondary, for: .disabled)
            button.titleLabel?.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 14, weight: .medium))
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.65
        }
        top.addSubview(closeButton)
        for item in [saveButton, counter, reportButton] { bottom.addSubview(item) }
        for item in [closeButton, saveButton, counter, reportButton] { item.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: topAnchor), top.leadingAnchor.constraint(equalTo: leadingAnchor), top.trailingAnchor.constraint(equalTo: trailingAnchor),
            top.bottomAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 16),
            closeButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 4),
            closeButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16),
            closeButton.widthAnchor.constraint(equalToConstant: 44), closeButton.heightAnchor.constraint(equalToConstant: 44),
            bottom.bottomAnchor.constraint(equalTo: bottomAnchor), bottom.leadingAnchor.constraint(equalTo: leadingAnchor), bottom.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottom.topAnchor.constraint(equalTo: saveButton.topAnchor, constant: -16),
            saveButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -4),
            saveButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16),
            saveButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44), saveButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            counter.centerXAnchor.constraint(equalTo: centerXAnchor), counter.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
            saveButton.trailingAnchor.constraint(lessThanOrEqualTo: counter.leadingAnchor, constant: -12),
            reportButton.leadingAnchor.constraint(greaterThanOrEqualTo: counter.trailingAnchor, constant: 12),
            reportButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -16),
            reportButton.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor), reportButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44), reportButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
        let line = UIView()
        line.backgroundColor = OutPickTheme.ColorToken.borderSubtle
        line.translatesAutoresizingMaskIntoConstraints = false
        bottom.addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16),
            line.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -16),
            line.bottomAnchor.constraint(equalTo: saveButton.topAnchor, constant: -8), line.heightAnchor.constraint(equalToConstant: 0.5)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        topGradient.frame = top.bounds
        bottomGradient.frame = bottom.bounds
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit is UIControl ? hit : nil
    }

    func render(index: Int, count: Int, saving: Bool) {
        counter.text = count > 1 ? String(format: "%02d / %02d", index + 1, count) : ""
        counter.accessibilityLabel = count > 1 ? "총 \(count)장 중 \(index + 1)번째 사진" : nil
        saveButton.setTitle(saving ? " 저장 중…" : " 저장", for: .normal)
        saveButton.isEnabled = !saving && count > 0
        saveButton.setTitleColor(saving ? OutPickTheme.ColorToken.accent : OutPickTheme.ColorToken.textSecondary, for: .disabled)
        saveButton.tintColor = saving ? OutPickTheme.ColorToken.accent : OutPickTheme.ColorToken.textPrimary
    }
}
