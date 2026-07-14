//
//  TagAliasDTO.swift
//  OutPick
//
//  Created by 김가윤 on 1/10/26.
//

import Foundation
import FirebaseFirestore

/// Firestore tagAliases 문서 ↔︎ Domain 변환 DTO
struct TagAliasDTO: Decodable {
    let raw: String
    let displayName: String
    let conceptId: String
    let createdAt: Timestamp?
    let updatedAt: Timestamp?

    func toDomain(documentID: String) throws -> TagAlias {
        guard !documentID.isEmpty else { throw MappingError.missingDocumentID }
        return TagAlias(
            id: documentID,
            raw: raw,
            displayName: displayName,
            conceptId: conceptId
        )
    }
}
