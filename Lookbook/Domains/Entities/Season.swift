//
//  Season.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation

/// 시즌 구분(SS / FW)
enum SeasonTerm: String, Codable, CaseIterable, Equatable {
    case ss
    case fw

    /// UI 표기용 텍스트
    var displayText: String {
        switch self {
        case .ss: return "S/S"
        case .fw: return "F/W"
        }
    }

    /// 정렬 우선순위(FW → SS)
    var sortOrder: Int {
        switch self {
        case .fw: return 0
        case .ss: return 1
        }
    }
}

/// 시즌 상태(운영/노출 상태)
enum SeasonStatus: String, Codable, CaseIterable, Equatable {
    case draft
    case published
    case archived
}

struct Season: Equatable, Codable, Identifiable {
    var id: SeasonID
    var brandID: BrandID

    /// 시즌 연도. 예: 2025 (2자리도 허용하되 4자리 권장)
    var year: Int

    /// 시즌 구분. 예: SS / FW
    var term: SeasonTerm

    /// 대표 이미지 Storage 경로(path)
    var coverPath: String?

    /// 시즌 간단 설명(목록 셀에 표시)
    var description: String

    /// 시즌 무드 태그(표현 단위). 예: "미니멀", "minimal" 등
    /// - 포스트 생성 시 그대로 복사해서 저장
    var tagIDs: [TagID]

    /// 시즌 무드 태그(의미/개념 단위).
    /// - 동의어/다국어(예: 미니멀/minimal/minimalism 등)를 하나의 concept로 묶어 검색/필터링에 사용
    /// - Firestore 기존 문서에 없을 수 있어 Optional로 유지
    var tagConceptIDs: [String]?

    /// 노출/운영 상태
    var status: SeasonStatus

    /// 시즌에 속한 포스트(룩) 개수 스냅샷
    var postCount: Int

    var createdAt: Date
    var updatedAt: Date

    /// UI 표기용 타이틀. 예: "25 F/W"
    var title: String {
        Season.formatTitle(year: year, term: term)
    }

    /// 기본 정렬(최신년도 → FW → SS → 최신 업데이트)
    static func defaultSort(_ lhs: Season, _ rhs: Season) -> Bool {
        if lhs.year != rhs.year { return lhs.year > rhs.year }
        if lhs.term.sortOrder != rhs.term.sortOrder { return lhs.term.sortOrder < rhs.term.sortOrder }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.createdAt > rhs.createdAt
    }
}

// MARK: - Helpers
extension Season {
    /// UI 표기용 타이틀을 생성합니다. (예: 2025 + FW → "25 F/W")
    fileprivate static func formatTitle(year: Int, term: SeasonTerm) -> String {
        let yy = normalizedYear(year)
        return String(format: "%02d %@", yy, term.displayText)
    }

    /// 4자리(2025) / 2자리(25) 모두 입력 가능하게 정규화
    fileprivate static func normalizedYear(_ year: Int) -> Int {
        if year >= 100 { return year % 100 }
        return year
    }
}
