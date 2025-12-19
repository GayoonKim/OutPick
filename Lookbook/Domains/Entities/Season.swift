//
//  Season.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation

struct Season: Equatable, Codable, Identifiable {
    var id: SeasonID
    var brandID: BrandID
    var title: String       // 예: "25 F/W"
    var coverURL: URL?
//    var startDate: Date?
//    var endDate: Date?

    /// 시즌 무드 태그(표현 단위). 예: "미니멀", "minimal" 등
    /// - 포스트 생성 시 그대로 복사해서 저장
    var tagIDs: [TagID]

    /// 시즌 무드 태그(의미/개념 단위).
    /// - 동의어/다국어(예: 미니멀/minimal/minimalism 등)를 하나의 concept로 묶어 검색/필터링에 사용
    /// - Firestore 기존 문서에 없을 수 있어 Optional로 유지
    var tagConceptIDs: [String]?

    var createdAt: Date
    var updatedAt: Date
}
