//
//  ImageLoading.swift
//  OutPick
//
//  Created by 김가윤 on 12/31/25.
//

import UIKit

protocol ImageLoading {
    /// 캐시 우선으로 이미지를 로드합니다.
    func loadImage(path: String, cacheKey: String, maxBytes: Int) async throws -> UIImage

    /// 여러 이미지를 병렬로 프리패치합니다. (실패는 무시 가능)
    func prefetch(items: [(path: String, cacheKey: String, maxBytes: Int)], concurrency: Int) async
}
