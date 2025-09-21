//
//  DateSeperatorCell.swift
//  OutPick
//
//  Created by 김가윤 on 5/7/25.
//

import Foundation
import UIKit

class DateSeperatorCell: UICollectionViewCell {
    static let reuseIdentifier = "DateSeperatorCell"
    
    private let dateLabelBackground: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = 15
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    private let dateLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .black
        label.textAlignment = .center
        label.backgroundColor = .clear
        label.layer.cornerRadius = 20
        label.translatesAutoresizingMaskIntoConstraints = false
        
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        dateLabelBackground.addSubview(dateLabel)
        contentView.addSubview(dateLabelBackground)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configureWithDate(_ dateText: String) {
        dateLabel.text = dateText
        
        NSLayoutConstraint.activate([
            dateLabel.centerXAnchor.constraint(equalTo: dateLabelBackground.centerXAnchor),
            dateLabel.centerYAnchor.constraint(equalTo: dateLabelBackground.centerYAnchor),
            dateLabel.topAnchor.constraint(equalTo: dateLabelBackground.topAnchor, constant: 10),
            dateLabel.bottomAnchor.constraint(equalTo: dateLabelBackground.bottomAnchor, constant: -10),
            
            dateLabelBackground.leadingAnchor.constraint(equalTo: dateLabel.leadingAnchor, constant: -10),
            dateLabelBackground.trailingAnchor.constraint(equalTo: dateLabel.trailingAnchor, constant: 10),
            dateLabelBackground.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            dateLabelBackground.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            dateLabelBackground.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            dateLabelBackground.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }
}
