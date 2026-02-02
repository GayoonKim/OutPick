//
//  ChatImagePreviewCell.swift
//  OutPick
//
//  Created by 김가윤 on 3/14/25.
//

import UIKit
import Kingfisher

class ChatImagePreviewCell: UICollectionViewCell {
    static let reuseIdentifier = "ChatImagePreviewCell"
    
    let imageView = UIImageView()

    override func prepareForReuse() {
        super.prepareForReuse()
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.isOpaque = true
        imageView.backgroundColor = .secondarySystemBackground
        imageView.accessibilityIgnoresInvertColors = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    func configure(with image: UIImage) {
        imageView.image = image
    }
    
    
}
