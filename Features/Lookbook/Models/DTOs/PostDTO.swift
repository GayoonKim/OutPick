//
//  PostDTO.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation
import FirebaseFirestore

// MARK: - 중첩 DTO: 미디어
struct MediaAssetDTO: Codable {
    let type: String
    let url: String
    let thumbnailURL: String?
    let width: Int?
    let height: Int?

    func toDomain() throws -> MediaAsset {
        guard let mediaType = MediaType(rawValue: type) else {
            throw MappingError.invalidEnumValue("MediaType: \(type)")
        }
        guard let url = URL(string: url) else {
            throw MappingError.invalidURL(url)
        }

        return MediaAsset(
            type: mediaType,
            url: url,
            thumbnailURL: thumbnailURL.flatMap(URL.init(string:)),
//            width: width,
//            height: height
        )
    }
}

// MARK: - 중첩 DTO: 지표
struct PostMetricsDTO: Codable {
    let likeCount: Int?
    let commentCount: Int?
    let replacementCount: Int?
    let saveCount: Int?
    let viewCount: Int?

    func toDomain() -> PostMetrics {
        PostMetrics(
            likeCount: likeCount ?? 0,
            commentCount: commentCount ?? 0,
            replacementCount: replacementCount ?? 0,
            saveCount: saveCount ?? 0,
            viewCount: viewCount
        )
    }
}

// MARK: - Post DTO
struct PostDTO: Codable {
    @DocumentID var id: String?

    /// 전역 조회(collectionGroup)까지 고려하면 문서에 brandID/seasonID를 "중복 저장"하는 전략도 많이 씁니다.
    /// - Note: 서브컬렉션(posts)이면 경로에서 주입해도 되고, 전역 조회가 필요하면 문서 필드로도 갖고 있는 편이 편합니다.
    let brandID: String?
    let seasonID: String?

    let authorID: String?
    let media: [MediaAssetDTO]
    let caption: String?
    let tagIDs: [String]?
    let metrics: PostMetricsDTO?
    let createdAt: Timestamp?
    let updatedAt: Timestamp?

    /// ✅ 권장: posts가 특정 brand/season 아래에 있을 때는 경로에서 주입
    func toDomain(brandID: BrandID, seasonID: SeasonID) throws -> LookbookPost {
        guard let id else { throw MappingError.missingDocumentID }

        let domainMetrics = (metrics ?? PostMetricsDTO(
            likeCount: nil,
            commentCount: nil,
            replacementCount: nil,
            saveCount: nil,
            viewCount: nil
        )).toDomain()

        return LookbookPost(
            id: PostID(value: id),
            brandID: brandID,
            seasonID: seasonID,
            authorID: authorID.map { UserID(value: $0) },
            media: try media.map { try $0.toDomain() },
            caption: caption,
            tagIDs: (tagIDs ?? []).map { TagID(value: $0) },
            metrics: domainMetrics,
            createdAt: createdAt?.dateValue() ?? Date(timeIntervalSince1970: 0),
            updatedAt: updatedAt?.dateValue() ?? Date(timeIntervalSince1970: 0)
        )
    }

    /// ✅ 선택: 전역 조회(collectionGroup) 등에서 문서 필드에 brandID/seasonID가 들어있는 경우
    func toDomainFromEmbeddedPathIDs() throws -> LookbookPost {
        guard let embeddedBrandID = brandID, !embeddedBrandID.isEmpty else {
            throw MappingError.missingRequiredField("brandID")
        }
        guard let embeddedSeasonID = seasonID, !embeddedSeasonID.isEmpty else {
            throw MappingError.missingRequiredField("seasonID")
        }
        return try toDomain(
            brandID: BrandID(value: embeddedBrandID),
            seasonID: SeasonID(value: embeddedSeasonID)
        )
    }
}
