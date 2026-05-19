// MARK: - CircularProgressHUD (small centered ring + percentage only)

import UIKit

final class CircularProgressHUD: UIView {

    private let ringLayer = CAShapeLayer()
    private let trackLayer = CAShapeLayer()
    private let percentLabel = UILabel()

    // Tunables
    private let ringLineWidth: CGFloat = 4
    private let ringSize: CGFloat = 25
    private let spacing: CGFloat = 8

    // Subviews
    private let container = UIView()
    private let ringView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // Make the whole HUD transparent and non-blocking to touches
        backgroundColor = .clear
        isUserInteractionEnabled = false

        // Container (no card, just intrinsic size around ring + percent)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .clear
        addSubview(container)

        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: centerXAnchor),
            container.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        // Ring view
        ringView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(ringView)

        NSLayoutConstraint.activate([
            ringView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            ringView.topAnchor.constraint(equalTo: container.topAnchor),
            ringView.widthAnchor.constraint(equalToConstant: ringSize),
            ringView.heightAnchor.constraint(equalToConstant: ringSize)
        ])

        // Percent label
        percentLabel.translatesAutoresizingMaskIntoConstraints = false
        percentLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        percentLabel.textColor = UIColor.label
        percentLabel.textAlignment = .center
        percentLabel.text = "0%"
        container.addSubview(percentLabel)

        NSLayoutConstraint.activate([
            percentLabel.topAnchor.constraint(equalTo: ringView.bottomAnchor, constant: spacing),
            percentLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            percentLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        // Path for ring & track
        let centerPoint = CGPoint(x: ringSize/2, y: ringSize/2)
        let circlePath = UIBezierPath(
            arcCenter: centerPoint,
            radius: (ringSize - ringLineWidth)/2,
            startAngle: -.pi/2,
            endAngle: 1.5 * .pi,
            clockwise: true
        )

        trackLayer.path = circlePath.cgPath
        trackLayer.strokeColor = UIColor.systemGray5.cgColor
        trackLayer.fillColor = UIColor.clear.cgColor
        trackLayer.lineWidth = ringLineWidth
        ringView.layer.addSublayer(trackLayer)

        ringLayer.path = circlePath.cgPath
        ringLayer.strokeColor = UIColor.label.cgColor
        ringLayer.fillColor = UIColor.clear.cgColor
        ringLayer.lineWidth = ringLineWidth
        ringLayer.lineCap = .round
        ringLayer.strokeEnd = 0
        ringView.layer.addSublayer(ringLayer)
    }

    func setProgress(_ fraction: Double) {
        let clamped = max(0.0, min(1.0, fraction))
        ringLayer.strokeEnd = CGFloat(clamped)
        percentLabel.text = "\(Int(clamped * 100))%"
    }

    // Kept for API compatibility; no-op since we removed the title
    func setTitle(_ text: String) { }

    func dismiss() {
        removeFromSuperview()
    }

    @discardableResult
    static func show(in view: UIView, title: String? = nil) -> CircularProgressHUD {
        let hud = CircularProgressHUD(frame: view.bounds)
        hud.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hud)

        NSLayoutConstraint.activate([
            hud.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hud.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hud.topAnchor.constraint(equalTo: view.topAnchor),
            hud.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        // title is ignored intentionally (percent-only HUD)
        return hud
    }
}
