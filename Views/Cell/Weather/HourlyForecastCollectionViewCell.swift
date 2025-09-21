//
//  HourlyForecastCollectionViewCell.swift
//  OutPick
//
//  Created by 김가윤 on 7/17/24.
//

import UIKit

class HourlyForecastCollectionViewCell: UICollectionViewCell {
    static let reuseIdentifier = "hourlyWeatherCell"

    // MARK: - ViewModel
    struct ViewModel {
        let timeText: String          // e.g., "오전 3시" / "15시"
        let tempText: String          // e.g., "22°"
        let icon: UIImage?            // optional icon image
        
        init(timeText: String, tempText: String, icon: UIImage?) {
            self.timeText = timeText
            self.tempText = tempText
            self.icon = icon
        }
    }

    // MARK: - UI
    private let timeLabel: UILabel = {
        let lb = UILabel()
        lb.font = .preferredFont(forTextStyle: .footnote)
        lb.textColor = .black
        lb.textAlignment = .center
        lb.adjustsFontForContentSizeCategory = true
        return lb
    }()

    private let iconImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.setContentHuggingPriority(.required, for: .vertical)
        iv.setContentCompressionResistancePriority(.required, for: .vertical)
        return iv
    }()

    private let tempLabel: UILabel = {
        let lb = UILabel()
        lb.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        lb.textColor = .label
        lb.textAlignment = .center
        lb.adjustsFontForContentSizeCategory = true
        return lb
    }()

    private lazy var vStack: UIStackView = {
        let st = UIStackView(arrangedSubviews: [timeLabel, iconImageView, tempLabel])
        st.axis = .vertical
        st.alignment = .center
        st.spacing = 6
        return st
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
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6)
        
        contentView.addSubview(vStack)
        vStack.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.translatesAutoresizingMaskIntoConstraints = false

        let g = contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            vStack.topAnchor.constraint(equalTo: g.topAnchor),
            vStack.leadingAnchor.constraint(equalTo: g.leadingAnchor),
            vStack.trailingAnchor.constraint(equalTo: g.trailingAnchor),
            vStack.bottomAnchor.constraint(equalTo: g.bottomAnchor),

            iconImageView.widthAnchor.constraint(equalToConstant: 30),
            iconImageView.heightAnchor.constraint(equalToConstant: 30)
        ])

        isAccessibilityElement = true
        accessibilityTraits = .staticText
    }

    // MARK: - Reuse
    override func prepareForReuse() {
        super.prepareForReuse()
        timeLabel.text = nil
        tempLabel.text = nil
        iconImageView.image = nil
        contentView.backgroundColor = .clear
        accessibilityLabel = nil
    }

    // MARK: - Configure
    func configure(with vm: ViewModel) {
        timeLabel.text = vm.timeText
        tempLabel.text = vm.tempText
        iconImageView.image = vm.icon
        iconImageView.isHidden = (vm.icon == nil)

        accessibilityLabel = "시간 \(vm.timeText), 온도 \(vm.tempText)"
    }
}
