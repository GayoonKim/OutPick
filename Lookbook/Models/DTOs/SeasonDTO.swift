//
//  SeasonDTO.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation
import FirebaseFirestore

struct SeasonDTO: Codable {
    @DocumentID var id: String?

    let title: String
    let coverURL: String?
//    let startDate: Timestamp?
//    let endDate: Timestamp?

    /// 시즌 무드 태그 (도메인에서는 [TagID]로 변환)
    let tagIDs: [String]?

    /// 시즌 무드 태그(의미/개념 단위). 동의어/다국어 검색을 위해 사용
    /// - Firestore 기존 문서에는 없을 수 있어 Optional로 유지
    let tagConceptIDs: [String]?

    /// 생성/수정 시각 (createdAt은 누락될 수 있어 방어적으로 처리)
    let createdAt: Timestamp?
    let updatedAt: Timestamp?

    /// Firestore DTO -> Domain 변환
    /// - Important: 시즌은 보통 `brands/{brandId}/seasons/{seasonId}` 경로에 있으므로 brandID는 "경로에서 주입"하는 방식을 추천합니다.
    func toDomain(brandID: BrandID) throws -> Season {
        guard let id else { throw MappingError.missingDocumentID }

        let domainTagIDs: [TagID] = (tagIDs ?? []).map { TagID(value: $0) }

        return Season(
            id: SeasonID(value: id),
            brandID: brandID,
            title: title,
            coverURL: coverURL.flatMap(URL.init(string:)),
//            startDate: startDate?.dateValue(),
//            endDate: endDate?.dateValue(),
            tagIDs: domainTagIDs,
            tagConceptIDs: tagConceptIDs,
            createdAt: createdAt?.dateValue() ?? Date(timeIntervalSince1970: 0),
            updatedAt: updatedAt?.dateValue() ?? Date(timeIntervalSince1970: 0)
        )
    }
}
