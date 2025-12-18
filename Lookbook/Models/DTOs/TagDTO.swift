//
//  TagDTO.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation
import FirebaseFirestore

struct TagDTO: Codable {
    @DocumentID var id: String?

    let name: String
    let normalized: String?

    func toDomain() throws -> Tag {
        guard let id else { throw MappingError.missingDocumentID }

        return Tag(
            id: TagID(value: id),
            name: name,
            normalized: normalized
        )
    }
}
