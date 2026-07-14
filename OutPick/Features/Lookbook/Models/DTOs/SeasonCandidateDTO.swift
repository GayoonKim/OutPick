//
//  SeasonCandidateDTO.swift
//  OutPick
//
//  Created by Codex on 4/23/26.
//

import Foundation
import FirebaseFirestore

struct SeasonCandidateDTO: Decodable {
    let brandID: String
    let title: String
    let seasonURL: String
    let coverImageURL: String?
    let sourceArchiveURL: String
    let extractionScore: Double?
    let sortIndex: Int?
    let status: String?
    let createdAt: Timestamp?
    let updatedAt: Timestamp?

    func toDomain(documentID: String) throws -> SeasonCandidate {
        guard !documentID.isEmpty else { throw MappingError.missingDocumentID }
        guard !brandID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MappingError.missingRequiredField("brandID")
        }

        return SeasonCandidate(
            id: documentID,
            brandID: BrandID(value: brandID),
            title: title,
            seasonURL: seasonURL,
            coverImageURL: coverImageURL,
            sourceArchiveURL: sourceArchiveURL,
            extractionScore: extractionScore ?? 0,
            sortIndex: sortIndex ?? Int.max,
            status: status ?? "pending",
            createdAt: createdAt?.dateValue() ?? Date(timeIntervalSince1970: 0),
            updatedAt: updatedAt?.dateValue() ?? Date(timeIntervalSince1970: 0)
        )
    }
}
