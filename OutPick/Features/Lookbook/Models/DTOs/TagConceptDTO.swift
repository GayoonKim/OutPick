//
//  TagConceptDTO.swift
//  OutPick
//
//  Created by 김가윤 on 1/10/26.
//

import Foundation
import FirebaseFirestore

/// Firestore tagConcepts 문서 ↔︎ Domain 변환 DTO
struct TagConceptDTO: Codable {
    @DocumentID var id: String?

    let displayName: String
    let createdAt: Timestamp?
    let updatedAt: Timestamp?

    func toDomain() throws -> TagConcept {
        guard let id else { throw MappingError.missingDocumentID }
        return TagConcept(id: id, displayName: displayName)
    }
}
