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
        configure(UIColor(white: 0.1, alpha: 0.03))
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    func configure(_ color: UIColor) {
        backgroundColor = color
    }

}
