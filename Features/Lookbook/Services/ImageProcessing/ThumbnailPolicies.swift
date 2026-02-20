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
    static let brandLogoList = ThumbnailPolicy(maxPixelSize: 768, quality: 0.88)

    /// 브랜드 상세/확대 프리뷰용 중간 해상도
    /// - Note: 원본보다 작지만 2~3배 확대에서도 디테일이 유지되도록 설정
    static let brandLogoDetail = ThumbnailPolicy(maxPixelSize: 2048, quality: 0.92)
    
    static let seasonCover = ThumbnailPolicy(maxPixelSize: 512, quality: 0.75)

    /// 프로젝트 공통 기본(= MediaManager 기본과 동일)
    static let `default` = ThumbnailPolicy.default
}
