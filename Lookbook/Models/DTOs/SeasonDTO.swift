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
    let startDate: Timestamp?
    let endDate: Timestamp?
    let updatedAt: Timestamp?

    /// Firestore DTO -> Domain 변환
    /// - Important: 시즌은 보통 `brands/{brandId}/seasons/{seasonId}` 경로에 있으므로 brandID는 "경로에서 주입"하는 방식을 추천합니다.
    func toDomain(brandID: BrandID) throws -> Season {
        guard let id else { throw MappingError.missingDocumentID }

        return Season(
            id: SeasonID(value: id),
            brandID: brandID,
            title: title,
            coverURL: coverURL.flatMap(URL.init(string:)),
            startDate: startDate?.dateValue(),
            endDate: endDate?.dateValue(),
            updatedAt: updatedAt?.dateValue() ?? Date(timeIntervalSince1970: 0)
        )
    }
}
