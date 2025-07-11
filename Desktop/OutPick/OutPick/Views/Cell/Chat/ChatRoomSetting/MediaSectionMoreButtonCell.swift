//
//  MediaSectionMoreButtonCollectionViewCell.swift
//  OutPick
//
//  Created by 김가윤 on 5/15/25.
//

import UIKit

class MediaSectionMoreButtonCell: UICollectionViewCell {
    static let reuseIdentifier = "MediaSectionMoreButtonCell"
    
    private lazy var moreImage: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "arrowshape.right.fill"))
        imageView.tintColor = .black
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 20
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        return imageView
    }()
    
    private lazy var moreLabel: UILabel = {
        let label = UILabel()
        label.text = "더보기"
        label.font = .systemFont(ofSize: 12, weight: .light)
        label.textAlignment = .center
        label.textColor = .black
        label.translatesAutoresizingMaskIntoConstraints = false
        
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        contentView.addSubview(moreImage)
        contentView.addSubview(moreLabel)
        
        NSLayoutConstraint.activate([
            moreImage.heightAnchor.constraint(equalToConstant: contentView.bounds.height/3),
            moreImage.widthAnchor.constraint(equalToConstant: contentView.bounds.width/3),
            moreImage.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            moreImage.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -3),
            moreLabel.topAnchor.constraint(equalTo: moreImage.bottomAnchor, constant: 3),
            moreLabel.centerXAnchor.constraint(equalTo: moreImage.centerXAnchor)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
