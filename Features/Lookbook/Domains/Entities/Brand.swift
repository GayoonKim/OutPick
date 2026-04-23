//
//  Brand.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation

enum BrandDiscoveryStatus: String, Codable, CaseIterable, Equatable {
    case idle
    case queued
    case running
    case success
    case failed
}

// MARK:- 핵심 엔티티들
struct Brand: Equatable, Codable, Identifiable {
    var id: BrandID
    var name: String
    var websiteURL: String?

    /// 목록/카드에서 사용하는 썸네일 Storage 경로
    var logoThumbPath: String?

    /// 상세/확대 프리뷰에서 사용하는 중간 해상도 Storage 경로
    var logoDetailPath: String?

    /// 상세/확대에서 사용하는 원본 Storage 경로
    var logoOriginalPath: String?

    /// (호환/편의) 예전 코드가 logoPath만 기대하는 경우를 위해 썸네일을 반환
    var logoPath: String? { logoThumbPath }

    /// 홈/목록에서 사용할 대표 로고 경로입니다.
    /// - Note: 썸네일이 없으면 detail, 그마저 없으면 original 순으로 폴백합니다.
    var listLogoPath: String? {
        if let logoThumbPath, !logoThumbPath.isEmpty {
            return logoThumbPath
        }
        if let logoDetailPath, !logoDetailPath.isEmpty {
            return logoDetailPath
        }
        if let logoOriginalPath, !logoOriginalPath.isEmpty {
            return logoOriginalPath
        }
        return nil
    }

    var isFeatured: Bool
    var discoveryStatus: BrandDiscoveryStatus
    var lastDiscoveryErrorMessage: String?
    var lastDiscoveryRequestedAt: Date?
    var lastDiscoveryCompletedAt: Date?
    var metrics: BrandMetrics
    var updatedAt: Date
}
