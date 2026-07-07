//
//  BrandImageCacheProtocol.swift
//  OutPick
//
//  Created by 김가윤 on 12/31/25.
//

import UIKit

protocol BrandImageCacheProtocol {
    /// 캐시 우선으로 이미지를 로드합니다.
    func loadImage(path: String, maxBytes: Int) async throws -> UIImage

    /// 같은 Storage path에 파일이 덮어써진 경우, 새 데이터를 캐시에 즉시 반영합니다.
    func storeImageData(_ data: Data, path: String) async throws

    /// 같은 Storage path가 덮어써졌거나 더 이상 유효하지 않을 때 캐시를 비웁니다.
    func removeImage(path: String) async

    /// 여러 이미지를 병렬로 프리패치합니다. (실패는 무시 가능)
    func prefetch(
        items: [(path: String, maxBytes: Int)],
        concurrency: Int,
        storePolicy: ImageCacheStorePolicy
    ) async
}

extension BrandImageCacheProtocol {
    /// 기본 프리패치는 메모리와 디스크를 함께 사용합니다.
    func prefetch(items: [(path: String, maxBytes: Int)], concurrency: Int) async {
        await prefetch(
            items: items,
            concurrency: concurrency,
            storePolicy: .memoryAndDisk
        )
    }
}
