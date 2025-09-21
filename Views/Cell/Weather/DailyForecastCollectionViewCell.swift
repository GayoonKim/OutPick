//
//  DailyForecastCollectionViewCell.swift
//  OutPick
//
//  Created by 김가윤 on 7/18/24.
//

import UIKit

class DailyForecastCollectionViewCell: UICollectionViewCell {
    static let reuseIdentifier = "dailyWeatherCell"

    // MARK: - ViewModel
    struct ViewModel {
        let dayText: String           // e.g., "오늘" / "목"
        let minMaxText: String        // e.g., "18° / 26°"
        let icon: UIImage?            // optional icon image
    }

    // MARK: - UI
    private let dayLabel: UILabel = {
        let lb = UILabel()
        lb.font = .preferredFont(forTextStyle: .subheadline)
        lb.textColor = .black
        lb.numberOfLines = 1
        lb.adjustsFontForContentSizeCategory = true
        lb.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        return lb
    }()

    private let iconImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.setContentHuggingPriority(.required, for: .horizontal)
        iv.setContentCompressionResistancePriority(.required, for: .horizontal)
        return iv
    }()

    private let minMaxLabel: UILabel = {
        let lb = UILabel()
        lb.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        lb.textColor = .secondaryLabel
        lb.textAlignment = .right
        lb.numberOfLines = 1
        lb.adjustsFontForContentSizeCategory = true
        lb.setContentCompressionResistancePriority(.required, for: .horizontal)
        return lb
    }()

    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        contentView.backgroundColor = .clear
        contentView.layer.cornerRadius = 10
        contentView.layer.masksToBounds = true
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)

        contentView.addSubview(dayLabel)
        contentView.addSubview(iconImageView)
        contentView.addSubview(minMaxLabel)
        dayLabel.translatesAutoresizingMaskIntoConstraints = false
        minMaxLabel.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.translatesAutoresizingMaskIntoConstraints = false

        let g = contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            // 좌측: 요일 라벨
            dayLabel.leadingAnchor.constraint(equalTo: g.leadingAnchor),
            dayLabel.centerYAnchor.constraint(equalTo: g.centerYAnchor),

            // 우측: 최저/최고 라벨
            minMaxLabel.trailingAnchor.constraint(equalTo: g.trailingAnchor),
            minMaxLabel.centerYAnchor.constraint(equalTo: g.centerYAnchor),

            // 가운데: 아이콘을 행의 정확한 중앙에 고정
            iconImageView.centerXAnchor.constraint(equalTo: g.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: g.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 28),
            iconImageView.heightAnchor.constraint(equalToConstant: 28),

            // 겹침 방지 여백(최소 8pt)
            dayLabel.trailingAnchor.constraint(lessThanOrEqualTo: iconImageView.leadingAnchor, constant: -8),
            minMaxLabel.leadingAnchor.constraint(greaterThanOrEqualTo: iconImageView.trailingAnchor, constant: 8)
        ])

        isAccessibilityElement = true
        accessibilityTraits = .staticText
    }

    // MARK: - Reuse
    override func prepareForReuse() {
        super.prepareForReuse()
        dayLabel.text = nil
        minMaxLabel.text = nil
        iconImageView.image = nil
        contentView.backgroundColor = .clear
        dayLabel.textColor = .label
        minMaxLabel.textColor = .secondaryLabel
        accessibilityLabel = nil
    }

    // MARK: - Configure
    func configure(with vm: ViewModel) {
        dayLabel.text = vm.dayText
        minMaxLabel.text = vm.minMaxText
        iconImageView.image = vm.icon
        iconImageView.isHidden = (vm.icon == nil)
        
        accessibilityLabel = "날짜 \(vm.dayText), 온도 \(vm.minMaxText)"
    }
}
