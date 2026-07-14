//
//  SeasonWriteDTO.swift
//  OutPick
//
//  Created by Codex on 7/14/26.
//

import FirebaseFirestore

/// 시즌 문서의 저장 payload입니다. 문서 identity는 Firestore 경로가 소유하므로 ID를 encode하지 않습니다.
struct SeasonWriteDTO: Encodable {
    let displayTitle: String
    let sourceTitle: String?
    let year: Int?
    let term: SeasonTerm?
    let coverPath: String?
    let coverRemoteURL: String?
    let description: String
    let tagIDs: [String]
    let tagConceptIDs: [String]?
    let status: SeasonStatus
    let deletionStatus: ContentDeletionStatus
    let assetSyncStatus: AssetSyncStatus
    let metadataStatus: SeasonMetadataStatus
    let metadataConfidence: Double?
    let sourceURL: String?
    let sourceImportJobID: String?
    let sourceSortIndex: Int?
    let postCount: Int
    let likeCount: Int
    let createdAt: Timestamp
    let updatedAt: Timestamp

    static func fromDomain(_ season: Season) -> SeasonWriteDTO {
        SeasonWriteDTO(
            displayTitle: season.displayTitle,
            sourceTitle: season.sourceTitle,
            year: season.year,
            term: season.term,
            coverPath: season.coverPath,
            coverRemoteURL: season.coverRemoteURL,
            description: season.description,
            tagIDs: season.tagIDs.map(\.value),
            tagConceptIDs: season.tagConceptIDs,
            status: season.status,
            deletionStatus: season.deletionStatus,
            assetSyncStatus: season.assetSyncStatus,
            metadataStatus: season.metadataStatus,
            metadataConfidence: season.metadataConfidence,
            sourceURL: season.sourceURL,
            sourceImportJobID: season.sourceImportJobID,
            sourceSortIndex: season.sourceSortIndex,
            postCount: season.postCount,
            likeCount: season.likeCount,
            createdAt: Timestamp(date: season.createdAt),
            updatedAt: Timestamp(date: season.updatedAt)
        )
    }
}
