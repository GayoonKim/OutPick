//
//  BrandDTO.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation
import FirebaseFirestore

struct BrandDTO: Codable {
    @DocumentID var id: String?

    let name: String
    let logoURL: String?
    let isFeatured: Bool?
    let updatedAt: Timestamp?

    /// Firestore DTO -> Domain 변환
    /// - Note: 스키마 변경에 대비해 optional을 허용하고, 여기서 기본값을 채웁니다.
    func toDomain() throws -> Brand {
        guard let id else { throw MappingError.missingDocumentID }

        return Brand(
            id: BrandID(value: id),
            name: name,
            logoURL: logoURL.flatMap(URL.init(string:)),
            isFeatured: isFeatured ?? false,
            updatedAt: updatedAt?.dateValue() ?? Date(timeIntervalSince1970: 0)
        )
    }
}
