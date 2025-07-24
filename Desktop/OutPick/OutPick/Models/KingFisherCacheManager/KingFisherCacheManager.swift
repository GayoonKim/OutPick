//
//  KingFisherCacheManager.swift
//  OutPick
//
//  Created by 김가윤 on 7/23/25.
//

import UIKit
import Kingfisher

final class KingFisherCacheManager {
    static let shared = KingFisherCacheManager()
    
    private init() {}

    /// Kingfisher 캐시에서 이미지 비동기 로드
    func loadImage(named name: String) async -> UIImage? {
        if let image = KingfisherManager.shared.cache.retrieveImageInMemoryCache(forKey: name) {
            return image
        }
        
        if let image = try? await KingfisherManager.shared.cache.retrieveImageInDiskCache(forKey: name) {
            return image
        }
        
        return nil
    }

    /// 이미지를 메모리 & 디스크 캐시에 저장
    func storeImage(_ image: UIImage, forKey key: String) {
        KingfisherManager.shared.cache.store(image, forKey: key)
    }

    /// 캐시에서 이미지 제거
    func removeImage(forKey key: String) {
        KingfisherManager.shared.cache.removeImage(forKey: key)
    }
}
