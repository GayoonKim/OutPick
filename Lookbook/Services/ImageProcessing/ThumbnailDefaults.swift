//
//  ThumbnailDefaults.swift
//  OutPick
//
//  Created by 김가윤 on 12/31/25.
//

import UIKit

/// 썸네일 기본값의 단일 소스(프로젝트 전체 공통)
enum ThumbnailDefaults {
    /// 기본 썸네일 긴 변(px)
    static let maxPixelSize: Int = 500

    /// 기본 JPEG 품질(0~1)
    static let quality: CGFloat = 0.5
}
