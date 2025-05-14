//
//  ChatRoomMediaCollectionViewCell.swift
//  OutPick
//
//  Created by 김가윤 on 5/14/25.
//

import UIKit

class ChatRoomMediaCollectionViewCell: UICollectionViewCell {
    static let reuseIdentifier = "ChatRoomMediaCell"
    
    private let imageVideoButtonImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "photo.on.rectangle.angled")
        imageView.tintColor = .systemGreen
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        return imageView
    }()
    
    private let imageVideoLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16)
        label.textColor = .black
        label.translatesAutoresizingMaskIntoConstraints = false
        
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        contentView.layer.cornerRadius = 20
        contentView.layer.masksToBounds = true

        addSubview(imageVideoButtonImageView)
        addSubview(imageVideoLabel)
        
        NSLayoutConstraint.activate([
            imageVideoButtonImageView.heightAnchor.constraint(equalToConstant: 25),
            imageVideoButtonImageView.widthAnchor.constraint(equalToConstant: 25),
            imageVideoButtonImageView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 10),
            imageVideoButtonImageView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            imageVideoButtonImageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            
            
            imageVideoLabel.centerYAnchor.constraint(equalTo: imageVideoButtonImageView.centerYAnchor),
            imageVideoLabel.leadingAnchor.constraint(equalTo: imageVideoButtonImageView.trailingAnchor, constant: 10)
        ])
    }
    
    func configureCell() {
        imageVideoLabel.text = "사진/동영상"
        backgroundColor = .white
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
