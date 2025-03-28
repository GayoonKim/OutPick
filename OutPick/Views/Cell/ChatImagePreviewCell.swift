//
//  ChatImagePreviewCell.swift
//  OutPick
//
//  Created by 김가윤 on 3/28/25.
//

import UIKit
import Foundation

class ChatImagePreviewCell: UICollectionViewCell {
    static let reuseIdentifier = "ChatImagePreviewCell"
    
    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        return imageView
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupImageView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupImageView() {
        contentView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 40),
            imageView.heightAnchor.constraint(equalToConstant: 40),
            ])
    }
    
    func configure(with image: UIImage) {
        print("ChatMessagePreviewCell 호출")
        imageView.image = image
    }
}
