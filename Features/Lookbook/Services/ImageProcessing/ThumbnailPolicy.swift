//
//  ThumbnailPolicy.swift
//  OutPick
//
//  Created by 김가윤 on 12/31/25.
//

import UIKit

/// 썸네일 생성 정책(크기/품질)을 한 덩어리로 관리합니다.
struct ThumbnailPolicy: Equatable {
    /// 가로/세로 중 더 긴 변의 최대 픽셀 크기
    let maxPixelSize: Int

    /// JPEG 압축 품질(0~1)
    let quality: CGFloat

    /// 프로젝트 기본값(= ThumbnailDefaults)
    static let `default` = ThumbnailPolicy(
        maxPixelSize: ThumbnailDefaults.maxPixelSize,
        quality: ThumbnailDefaults.quality
    )
}
