//
//  OutPickTabBar.swift
//  OutPick
//
//  Created by Codex on 6/30/26.
//

import UIKit

final class OutPickTabBar: UITabBar {
    private let preferredContentHeight: CGFloat = 54

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        var fittingSize = super.sizeThatFits(size)
        fittingSize.height = preferredContentHeight + (window?.safeAreaInsets.bottom ?? 0)
        return fittingSize
    }
}
