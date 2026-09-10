import UIKit

/// 사진은 옅게 덮고 진행 표시는 별도 레이어로 선명하게 유지한다.
final class ChatMediaUploadProgressView: UIView {
    private let badge = UIView()
    private let track = CAShapeLayer()
    private let ring = CAShapeLayer()
    private let countLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityIdentifier = "chat.mediaUpload.progress"
        backgroundColor = UIColor.black.withAlphaComponent(0.28)
        clipsToBounds = true
        layer.cornerRadius = 12
        badge.backgroundColor = UIColor.black.withAlphaComponent(0.78)
        badge.layer.cornerRadius = 26
        addSubview(badge)
        for shape in [track, ring] {
            shape.fillColor = UIColor.clear.cgColor
            shape.lineWidth = 4
            shape.lineCap = .round
            badge.layer.addSublayer(shape)
        }
        track.strokeColor = UIColor.white.withAlphaComponent(0.25).cgColor
        ring.strokeColor = UIColor.white.cgColor
        countLabel.textColor = .white
        countLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        countLabel.textAlignment = .center
        badge.addSubview(countLabel)
        reset()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        badge.frame = CGRect(x: (bounds.width - 52) / 2, y: (bounds.height - 52) / 2, width: 52, height: 52)
        countLabel.frame = badge.bounds
        let path = UIBezierPath(arcCenter: CGPoint(x: 26, y: 26), radius: 17,
            startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: true).cgPath
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for shape in [track, ring] { shape.frame = badge.bounds; shape.path = path }
        CATransaction.commit()
    }

    func show(progress: Double?) {
        countLabel.isHidden = true
        isHidden = false
        badge.isHidden = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let progress, progress.isFinite, progress < 1 {
            let fraction = min(1, max(0, progress))
            ring.removeAnimation(forKey: "pending")
            ring.strokeEnd = max(0.02, fraction)
            accessibilityLabel = "사진 전송 중"
            accessibilityValue = "\(Int(fraction * 100))%"
        } else {
            ring.strokeEnd = 0.25
            accessibilityLabel = "전송 완료 확인 중"
            accessibilityValue = nil
            if ring.animation(forKey: "pending") == nil, !UIAccessibility.isReduceMotionEnabled {
                let animation = CABasicAnimation(keyPath: "transform.rotation.z")
                animation.fromValue = 0
                animation.toValue = CGFloat.pi * 2
                animation.duration = 0.9
                animation.repeatCount = .infinity
                ring.add(animation, forKey: "pending")
            }
        }
        CATransaction.commit()
    }

    func showFailure() {
        isHidden = false
        badge.isHidden = true
        ring.removeAnimation(forKey: "pending")
        accessibilityLabel = "전송 실패"
        accessibilityValue = nil
    }

    func showWaiting(count: Int) {
        isHidden = false
        badge.isHidden = false
        countLabel.isHidden = false
        countLabel.text = "\(count)장"
        ring.removeAnimation(forKey: "pending")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.strokeEnd = 1
        CATransaction.commit()
        accessibilityLabel = "전송 대기"
        accessibilityValue = "\(count)장"
    }

    func reset() {
        isHidden = true
        ring.removeAllAnimations()
        countLabel.text = nil
        countLabel.isHidden = true
        accessibilityLabel = nil
        accessibilityValue = nil
    }
}
