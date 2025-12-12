//
//  BackgroundDecorationView.swift
//  OutPick
//
//  Created by 김가윤 on 11/11/24.
//

import UIKit

class BackgroundDecorationView: UICollectionReusableView {
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension BackgroundDecorationView {
    func configure() {
        backgroundColor = UIColor(white: 0.6, alpha: 0.3)
        self.layer.cornerRadius = 16
        self.layer.masksToBounds = true
    }
}
