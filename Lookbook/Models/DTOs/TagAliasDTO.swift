//
//  TagAliasDTO.swift
//  OutPick
//
//  Created by 김가윤 on 1/10/26.
//

import Foundation
import FirebaseFirestore

/// Firestore tagAliases 문서 ↔︎ Domain 변환 DTO
struct TagAliasDTO: Codable {
    @DocumentID var id: String?

    let raw: String
    let displayName: String
    let conceptId: String
    let createdAt: Timestamp?
    let updatedAt: Timestamp?

    func toDomain() throws -> TagAlias {
        guard let id else { throw MappingError.missingDocumentID }
        return TagAlias(
            id: id,
            raw: raw,
            displayName: displayName,
            conceptId: conceptId
        )
    }
}
