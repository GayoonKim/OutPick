//
//  ImageCacheManager.swift
//  OutPick
//
//  Created by 김가윤 on 1/7/25.
//

import UIKit

final class ImageCacheManager {
    static let shared = NSCache<NSString, UIImage>()
    
    private init() {}
}
