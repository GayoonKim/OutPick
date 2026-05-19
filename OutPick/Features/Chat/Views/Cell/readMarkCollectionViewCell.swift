//
//  readMarkCollectionViewCell.swift
//  OutPick
//
//  Created by 김가윤 on 8/14/25.
//

import UIKit

class readMarkCollectionViewCell: UICollectionViewCell {
    static let reuseIdentifier = "readMarkCell"
    
    private let readMarkLabelBackground: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = 15
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    private let readMarkLabel: UILabel = {
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
        
        readMarkLabelBackground.addSubview(readMarkLabel)
        contentView.addSubview(readMarkLabelBackground)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        readMarkLabel.text = "여기까지 읽으셨습니다."
        
        NSLayoutConstraint.activate([
            readMarkLabel.centerXAnchor.constraint(equalTo: readMarkLabelBackground.centerXAnchor),
            readMarkLabel.centerYAnchor.constraint(equalTo: readMarkLabelBackground.centerYAnchor),
            readMarkLabel.topAnchor.constraint(equalTo: readMarkLabelBackground.topAnchor, constant: 10),
            readMarkLabel.bottomAnchor.constraint(equalTo: readMarkLabelBackground.bottomAnchor, constant: -10),
            
            readMarkLabelBackground.leadingAnchor.constraint(equalTo: readMarkLabel.leadingAnchor, constant: -10),
            readMarkLabelBackground.trailingAnchor.constraint(equalTo: readMarkLabel.trailingAnchor, constant: 10),
            readMarkLabelBackground.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            readMarkLabelBackground.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            readMarkLabelBackground.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            readMarkLabelBackground.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }
}
