//
//  Brand.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation

// MARK:- 핵심 엔티티들
struct Brand: Equatable, Codable, Identifiable {
    var id: BrandID
    var name: String

    /// 목록/카드에서 사용하는 썸네일 Storage 경로
    var logoThumbPath: String?

    /// 상세/확대에서 사용하는 원본 Storage 경로
    var logoOriginalPath: String?

    /// (호환/편의) 예전 코드가 logoPath만 기대하는 경우를 위해 썸네일을 반환
    var logoPath: String? { logoThumbPath }

    var isFeatured: Bool
    var metrics: BrandMetrics
    var updatedAt: Date
}
