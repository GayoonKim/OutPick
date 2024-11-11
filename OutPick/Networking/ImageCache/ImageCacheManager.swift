//
//  ImageCacheManager.swift
//  OutPick
//
//  Created by 김가윤 on 11/1/24.
//

import UIKit

final class ImageCacheManager {
    static let shared = NSCache<NSString, UIImage>()
    
    private init() {}
}
