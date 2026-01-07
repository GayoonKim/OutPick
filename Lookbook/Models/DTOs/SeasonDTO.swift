//
//  SeasonDTO.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation
import FirebaseFirestore

/// Firestore Season 문서 ↔︎ Domain Season 변환용 DTO
/// - Note: 시즌 문서는 보통 `brands/{brandId}/seasons/{seasonId}` 경로에 있으므로 `brandID`는 "경로에서 주입"하는 방식을 권장합니다.
struct SeasonDTO: Codable {
    @DocumentID var id: String?

    let year: Int
    let term: SeasonTerm

    /// 대표 이미지 Storage 경로(path)
    let coverPath: String?

    /// 시즌 간단 설명(목록 셀에 표시)
    let description: String

    /// 시즌 무드 태그 (도메인에서는 [TagID]로 변환)
    let tagIDs: [String]?

    /// 시즌 무드 태그(의미/개념 단위). 동의어/다국어 검색을 위해 사용
    /// - Firestore 문서에 없을 수 있어 Optional로 유지
    let tagConceptIDs: [String]?

    /// 노출/운영 상태 (문서에 없을 수 있어 Optional)
    let status: SeasonStatus?

    /// 시즌에 속한 포스트(룩) 개수 스냅샷 (문서에 없을 수 있어 Optional)
    let postCount: Int?

    /// 생성/수정 시각 (createdAt은 누락될 수 있어 방어적으로 처리)
    let createdAt: Timestamp?
    let updatedAt: Timestamp?

    /// Firestore DTO -> Domain 변환
    func toDomain(brandID: BrandID) throws -> Season {
        guard let id else { throw MappingError.missingDocumentID }

        let domainTagIDs: [TagID] = (tagIDs ?? []).map { TagID(value: $0) }

        return Season(
            id: SeasonID(value: id),
            brandID: brandID,
            year: year,
            term: term,
            coverPath: coverPath,
            description: description,
            tagIDs: domainTagIDs,
            tagConceptIDs: tagConceptIDs,
            status: status ?? .published,
            postCount: postCount ?? 0,
            createdAt: createdAt?.dateValue() ?? Date(timeIntervalSince1970: 0),
            updatedAt: updatedAt?.dateValue() ?? Date(timeIntervalSince1970: 0)
        )
    }
}

// MARK: - Domain -> DTO
extension SeasonDTO {
    /// 저장용 DTO 생성(문서 생성/업데이트 시 사용)
    static func fromDomain(_ season: Season) -> SeasonDTO {
        SeasonDTO(
            id: season.id.value,
            year: season.year,
            term: season.term,
            coverPath: season.coverPath,
            description: season.description,
            tagIDs: season.tagIDs.map { $0.value },
            tagConceptIDs: season.tagConceptIDs,
            status: season.status,
            postCount: season.postCount,
            createdAt: Timestamp(date: season.createdAt),
            updatedAt: Timestamp(date: season.updatedAt)
        )
    }
}
