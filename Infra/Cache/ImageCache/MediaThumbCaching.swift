//
//  MediaThumbCaching.swift
//  OutPick
//
//  Created by 김가윤 on 2/7/26.
//

import UIKit

/// 썸네일 캐시 인터페이스 (B안: 메모리/디스크 호출 분리)
protocol MediaThumbCaching: Sendable {

    /// 디스크에만 저장 (Data 그대로)
    func storeToDisk(data: Data, forKey key: String) async

    /// 메모리에만 저장 (UIImage)
    func storeToMemory(image: UIImage, forKey key: String) async

    /// UIImage 로드: memory → (in-flight) → disk decode → memory 적재
    func loadImage(forKey key: String) async -> UIImage?

    /// Data 로드: disk only (프리페치/백업 용도)
    func loadData(forKey key: String) async -> Data?
}
