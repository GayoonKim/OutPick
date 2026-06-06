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
    let phase: SeasonImportJobPhase
    let sourceURL: String
    let sourceCandidateID: String?
    let sourceImportJobID: String?
    let targetSeasonID: String?
    let requestedBy: String
    let errorMessage: String?
    let assetCompletedCount: Int?
    let assetFailedCount: Int?
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
            phase: phase,
            sourceURL: sourceURL,
            sourceCandidateID: sourceCandidateID,
            sourceImportJobID: sourceImportJobID,
            targetSeasonID: targetSeasonID.map { SeasonID(value: $0) },
            requestedBy: requestedBy,
            errorMessage: errorMessage,
            assetCompletedCount: assetCompletedCount ?? 0,
            assetFailedCount: assetFailedCount ?? 0,
            createdAt: createdAt?.dateValue() ?? Date(timeIntervalSince1970: 0),
            updatedAt: updatedAt?.dateValue() ?? Date(timeIntervalSince1970: 0)
        )
    }
}
