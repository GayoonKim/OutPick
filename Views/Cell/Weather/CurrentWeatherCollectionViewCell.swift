//
//  CurrentWeatherCollectionViewCell.swift
//  OutPick
//
//  Created by 김가윤 on 7/11/24.
//

import UIKit

// 현재 날씨 정보를 표시하는 컬렉션 뷰 셀
class CurrentWeatherCollectionViewCell: UICollectionViewCell {
    static let reuseIdentifier = "currentWeatherCell"

    // MARK: - ViewModel for decoupled configuration
    struct ViewModel {
        let city: String
        let tempText: String           // e.g., "23°"
        let descriptionText: String    // e.g., "맑음"
        let minMaxText: String         // e.g., "최저 18° / 최고 26°"
    }

    // MARK: - UI
    private let container: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        return view
    }()
    
    private let cityLabel: UILabel = {
        let lb = UILabel()
        lb.font = .preferredFont(forTextStyle: .headline)
        lb.textColor = .black
        lb.numberOfLines = 1
        lb.adjustsFontForContentSizeCategory = true
        return lb
    }()

    private let tempLabel: UILabel = {
        let lb = UILabel()
        // 굵고 크게, 숫자 가독성 향상
        lb.font = .systemFont(ofSize: 40, weight: .medium)
        lb.textColor = .black
        lb.numberOfLines = 1
        lb.adjustsFontForContentSizeCategory = true
        return lb
    }()

    private let descriptionLabel: UILabel = {
        let lb = UILabel()
        lb.font = .preferredFont(forTextStyle: .subheadline)
        lb.textColor = .black
        lb.numberOfLines = 1
        lb.adjustsFontForContentSizeCategory = true
        return lb
    }()

    private let minMaxLabel: UILabel = {
        let lb = UILabel()
        lb.font = .preferredFont(forTextStyle: .footnote)
        lb.textColor = .black
        lb.numberOfLines = 1
        lb.adjustsFontForContentSizeCategory = true
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
        // 셀 스타일
        contentView.backgroundColor = .white
        contentView.layer.cornerRadius = 12
        contentView.layer.masksToBounds = true
        contentView.directionalLayoutMargins = .init(top: 20, leading: 12, bottom: 30, trailing: 12)

        contentView.addSubview(container)
        container.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(cityLabel)
        container.addSubview(tempLabel)
        container.addSubview(descriptionLabel)
        container.addSubview(minMaxLabel)
        cityLabel.translatesAutoresizingMaskIntoConstraints = false
        tempLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        minMaxLabel.translatesAutoresizingMaskIntoConstraints = false
        let g = contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: g.topAnchor),
            container.leadingAnchor.constraint(equalTo: g.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: g.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: g.bottomAnchor),
            
            cityLabel.topAnchor.constraint(equalTo: container.topAnchor),
            cityLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            
            tempLabel.topAnchor.constraint(equalTo: cityLabel.bottomAnchor, constant: 3),
            tempLabel.centerXAnchor.constraint(equalTo: cityLabel.centerXAnchor),
            
            descriptionLabel.topAnchor.constraint(equalTo: tempLabel.bottomAnchor),
            descriptionLabel.centerXAnchor.constraint(equalTo: cityLabel.centerXAnchor),
            
            minMaxLabel.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor),
            minMaxLabel.centerXAnchor.constraint(equalTo: cityLabel.centerXAnchor),
            minMaxLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        // 접근성
        isAccessibilityElement = true
        accessibilityTraits = .staticText
    }

    // MARK: - Reuse
    override func prepareForReuse() {
        super.prepareForReuse()
        cityLabel.text = nil
        tempLabel.text = nil
        descriptionLabel.text = nil
        minMaxLabel.text = nil
        accessibilityLabel = nil
    }

    // MARK: - Configure
    func configure(with vm: ViewModel) {
        cityLabel.text = vm.city
        tempLabel.text = vm.tempText
        descriptionLabel.text = vm.descriptionText
        minMaxLabel.text = vm.minMaxText

        accessibilityLabel = "현재 날씨, \(vm.city), 온도 \(vm.tempText), \(vm.descriptionText), \(vm.minMaxText)"
    }
}
