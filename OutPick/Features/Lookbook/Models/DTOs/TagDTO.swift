//
//  TagDTO.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation
import FirebaseFirestore

struct TagDTO: Decodable {
    let name: String
    let normalized: String?

    func toDomain(documentID: String) throws -> Tag {
        guard !documentID.isEmpty else { throw MappingError.missingDocumentID }

        return Tag(
            id: TagID(value: documentID),
            name: name,
            normalized: normalized
        )
    }
}
