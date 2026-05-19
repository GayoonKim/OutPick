//
//  SeasonImportJobDTO.swift
//  OutPick
//
//  Created by Codex on 4/23/26.
//

import Foundation
import FirebaseFirestore

struct SeasonImportJobDTO: Codable {
    @DocumentID var id: String?

    let brandID: String
    let jobType: SeasonImportJobType
    let status: SeasonImportJobStatus
    let sourceURL: String
    let sourceCandidateID: String?
    let requestedBy: String
    let errorMessage: String?
    let createdAt: Timestamp?
    let updatedAt: Timestamp?

    func toDomain() throws -> SeasonImportJob {
        guard let id else { throw MappingError.missingDocumentID }
        guard !brandID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MappingError.missingRequiredField("brandID")
        }

        return SeasonImportJob(
            id: id,
            brandID: BrandID(value: brandID),
            jobType: jobType,
            status: status,
            sourceURL: sourceURL,
            sourceCandidateID: sourceCandidateID,
            requestedBy: requestedBy,
            errorMessage: errorMessage,
            createdAt: createdAt?.dateValue() ?? Date(timeIntervalSince1970: 0),
            updatedAt: updatedAt?.dateValue() ?? Date(timeIntervalSince1970: 0)
        )
    }
}
