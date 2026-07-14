//
//  TagConceptDTO.swift
//  OutPick
//
//  Created by 김가윤 on 1/10/26.
//

import Foundation
import FirebaseFirestore

/// Firestore tagConcepts 문서 ↔︎ Domain 변환 DTO
struct TagConceptDTO: Decodable {
    let displayName: String
    let createdAt: Timestamp?
    let updatedAt: Timestamp?

    func toDomain(documentID: String) throws -> TagConcept {
        guard !documentID.isEmpty else { throw MappingError.missingDocumentID }
        return TagConcept(id: documentID, displayName: displayName)
    }
}
