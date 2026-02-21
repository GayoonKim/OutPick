//
//  BrandImageCache.swift
//  OutPick
//
//  Created by 김가윤 on 12/31/25.
//

import UIKit

/// 브랜드 로고(썸네일/디테일/원본 폴백) 로딩을 담당하는 스토어
final class BrandImageCache: BrandImageCacheProtocol {
    private let pipeline: ImageCachePipeline

    init(
        storage: StorageServiceProtocol = LookbookStorageService(),
        pipeline: ImageCachePipeline? = nil
    ) {
        self.pipeline = pipeline ?? ImageCachePipeline { [storage] path, maxBytes in
            try await storage.downloadImage(from: path, maxSize: maxBytes)
        }
    }

    func loadImage(path: String, maxBytes: Int) async throws -> UIImage {
        try await pipeline.loadImage(path: path, maxBytes: maxBytes)
    }

    func prefetch(items: [(path: String, maxBytes: Int)], concurrency: Int) async {
        await pipeline.prefetch(items: items, concurrency: concurrency)
    }
}
