//
//  MainTabBarWithCorners.swift
//  OutPick
//
//  Created by 김가윤 on 12/17/24.
//

import UIKit

class MainTabBarWithCorners: UITabBar {
    
    @IBInspectable var color: UIColor?
    @IBInspectable var radii: CGFloat = 20
    
    private var shapeLayer: CALayer?
    
    override func draw(_ rect: CGRect) {
        addShape()
    }
    
    private func addShape() {
        let shapeLayer = CAShapeLayer()
        
        shapeLayer.path = createPath()
        shapeLayer.strokeColor = UIColor.lightGray.cgColor
        shapeLayer.fillColor = color?.cgColor ?? UIColor.white.cgColor
        shapeLayer.lineWidth = 1
        shapeLayer.shadowColor = UIColor.lightGray.cgColor
        shapeLayer.shadowOffset = CGSize(width: 0, height: -2);
        shapeLayer.shadowOpacity = 0.21
        shapeLayer.shadowRadius = 8
        shapeLayer.shadowPath =  UIBezierPath(roundedRect: bounds, cornerRadius: radii).cgPath
        
        if let oldShapeLayer = self.shapeLayer {
            layer.replaceSublayer(oldShapeLayer, with: shapeLayer)
        } else {
            layer.insertSublayer(shapeLayer, at: 0)
        }
        
        self.shapeLayer = shapeLayer
    }
    
    private func createPath() -> CGPath {
        let path = UIBezierPath(
            roundedRect: bounds,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(width: radii, height: 0.0))
        
        return path.cgPath
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        self.isTranslucent = true
        var tabFrame = self.frame
        tabFrame.size.height = 65 + safeAreaInsets.bottom
        tabFrame.origin.y = self.frame.origin.y + self.frame.height - 65 - safeAreaInsets.bottom
        self.layer.cornerRadius = 10
        self.frame = tabFrame
        self.items?.forEach({ $0.titlePositionAdjustment = UIOffset(horizontal: 0.0, vertical: -5.0) })
    }
    
}
