//
//  MemoryImageCache.swift
//  OutPick
//
//  Created by 김가윤 on 12/31/25.
//

import UIKit

final class MemoryImageCache: ImageCaching {
    private let cache = NSCache<NSString, UIImage>()

    init(countLimit: Int = 300) {
        cache.countLimit = countLimit
    }

    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func setImage(_ image: UIImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }

    func removeImage(forKey key: String) {
        cache.removeObject(forKey: key as NSString)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}
