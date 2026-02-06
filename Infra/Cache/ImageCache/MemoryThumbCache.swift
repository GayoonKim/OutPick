//
//  MemoryThumbCache.swift
//  OutPick
//
//  Created by 김가윤 on 2/7/26.
//

import UIKit

/// NSCache 기반 메모리 캐시
final class MemoryThumbCache {
    private let cache = NSCache<NSString, UIImage>()

    init(totalCostLimitBytes: Int) {
        cache.totalCostLimit = totalCostLimitBytes
    }

    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func set(_ image: UIImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString, cost: image.estimatedBytes)
    }
}

private extension UIImage {
    /// 대략적인 메모리 비용 추정(정확값 아님). 추측입니다.
    var estimatedBytes: Int {
        let scale = self.scale
        let w = Int(self.size.width * scale)
        let h = Int(self.size.height * scale)
        return max(1, w) * max(1, h) * 4
    }
}
