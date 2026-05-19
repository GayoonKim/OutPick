//
//  SeasonDTO.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation
import FirebaseFirestore

/// Firestore Season 문서 ↔︎ Domain Season 변환용 DTO
/// - Note: 시즌 문서는 보통 `brands/{brandId}/seasons/{seasonId}` 경로에 있으므로 `brandID`는 "경로에서 주입"을 권장합니다.
struct SeasonDTO: Codable {
    @DocumentID var id: String?

    let displayTitle: String
    let sourceTitle: String?
    let year: Int?
    let term: SeasonTerm?

    /// 대표 이미지 Storage 경로(path)
    let coverPath: String?

    /// 원본 사이트 대표 이미지 URL
    let coverRemoteURL: String?

    /// 시즌 간단 설명(목록 셀에 표시)
    let description: String

    /// 시즌 무드 태그 (도메인에서는 [TagID]로 변환)
    let tagIDs: [String]?

    /// 시즌 무드 태그(의미/개념 단위)
    let tagConceptIDs: [String]?

    /// 노출/운영 상태 (문서에 없을 수 있어 Optional)
    let status: SeasonStatus

    /// 에셋 동기화 상태
    let assetSyncStatus: AssetSyncStatus

    /// 메타데이터 확정 상태
    let metadataStatus: SeasonMetadataStatus

    /// 메타데이터 추론 신뢰도
    let metadataConfidence: Double?

    /// 원본 시즌 상세 URL
    let sourceURL: String?

    /// import job ID
    let sourceImportJobID: String?

    /// 원본 목록 페이지 정렬 순서
    let sourceSortIndex: Int?

    /// 시즌에 속한 포스트(룩) 개수 스냅샷
    let postCount: Int

    /// 생성/수정 시각
    let createdAt: Timestamp?
    let updatedAt: Timestamp?

    func toDomain(brandID: BrandID) throws -> Season {
        guard let id else { throw MappingError.missingDocumentID }
        let trimmedDisplayTitle = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDisplayTitle.isEmpty else {
            throw MappingError.missingRequiredField("displayTitle")
        }

        let domainTagIDs: [TagID] = (tagIDs ?? []).map { TagID(value: $0) }

        return Season(
            id: SeasonID(value: id),
            brandID: brandID,
            displayTitle: trimmedDisplayTitle,
            sourceTitle: sourceTitle,
            year: year,
            term: term,
            coverPath: coverPath,
            coverRemoteURL: coverRemoteURL,
            description: description,
            tagIDs: domainTagIDs,
            tagConceptIDs: tagConceptIDs,
            status: status,
            assetSyncStatus: assetSyncStatus,
            metadataStatus: metadataStatus,
            metadataConfidence: metadataConfidence,
            sourceURL: sourceURL,
            sourceImportJobID: sourceImportJobID,
            sourceSortIndex: sourceSortIndex,
            postCount: postCount,
            createdAt: createdAt?.dateValue() ?? Date(timeIntervalSince1970: 0),
            updatedAt: updatedAt?.dateValue() ?? Date(timeIntervalSince1970: 0)
        )
    }
}

// MARK: - Domain -> DTO
extension SeasonDTO {
    static func fromDomain(_ season: Season) -> SeasonDTO {
        SeasonDTO(
            id: season.id.value,
            displayTitle: season.displayTitle,
            sourceTitle: season.sourceTitle,
            year: season.year,
            term: season.term,
            coverPath: season.coverPath,
            coverRemoteURL: season.coverRemoteURL,
            description: season.description,
            tagIDs: season.tagIDs.map { $0.value },
            tagConceptIDs: season.tagConceptIDs,
            status: season.status,
            assetSyncStatus: season.assetSyncStatus,
            metadataStatus: season.metadataStatus,
            metadataConfidence: season.metadataConfidence,
            sourceURL: season.sourceURL,
            sourceImportJobID: season.sourceImportJobID,
            sourceSortIndex: season.sourceSortIndex,
            postCount: season.postCount,
            createdAt: Timestamp(date: season.createdAt),
            updatedAt: Timestamp(date: season.updatedAt)
        )
    }
}
