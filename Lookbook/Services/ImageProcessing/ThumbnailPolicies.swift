//
//  ThumbnailPolicies.swift
//  OutPick
//
//  Created by 김가윤 on 12/31/25.
//

import UIKit

/// 화면/도메인별로 자주 쓰는 정책들을 모아둡니다.
enum ThumbnailPolicies {

    /// 브랜드 목록/카드용 로고 썸네일 (원하면 값 조절)
    static let brandLogoList = ThumbnailPolicy(
        maxPixelSize: 768,
        quality: 0.88
    )

    /// 프로젝트 공통 기본(= MediaManager 기본과 동일)
    static let `default` = ThumbnailPolicy.default
}
