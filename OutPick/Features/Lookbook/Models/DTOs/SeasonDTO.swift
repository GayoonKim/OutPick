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
struct SeasonDTO: Decodable {
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

    /// 삭제 lifecycle 상태. 기존 문서 호환을 위해 없으면 active로 처리합니다.
    let deletionStatus: ContentDeletionStatus?

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

    /// 시즌 좋아요 수 스냅샷
    let likeCount: Int?

    /// 생성/수정 시각
    let createdAt: Timestamp?
    let updatedAt: Timestamp?

    func toDomain(documentID: String, brandID: BrandID) throws -> Season {
        guard !documentID.isEmpty else { throw MappingError.missingDocumentID }
        let trimmedDisplayTitle = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDisplayTitle.isEmpty else {
            throw MappingError.missingRequiredField("displayTitle")
        }

        let domainTagIDs: [TagID] = (tagIDs ?? []).map { TagID(value: $0) }

        return Season(
            id: SeasonID(value: documentID),
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
            deletionStatus: deletionStatus ?? .active,
            assetSyncStatus: assetSyncStatus,
            metadataStatus: metadataStatus,
            metadataConfidence: metadataConfidence,
            sourceURL: sourceURL,
            sourceImportJobID: sourceImportJobID,
            sourceSortIndex: sourceSortIndex,
            postCount: postCount,
            likeCount: max(0, likeCount ?? 0),
            createdAt: createdAt?.dateValue() ?? Date(timeIntervalSince1970: 0),
            updatedAt: updatedAt?.dateValue() ?? Date(timeIntervalSince1970: 0)
        )
    }
}
