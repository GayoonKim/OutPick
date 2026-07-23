//
//  SeasonImportJobDTO.swift
//  OutPick
//
//  Created by Codex on 4/23/26.
//

import Foundation
import FirebaseFirestore

struct SeasonImportJobDTO: Decodable {
    let brandID: String
    let jobType: SeasonImportJobType
    let status: SeasonImportJobStatus
    let phase: SeasonImportJobPhase
    let sourceURL: String
    let seasonTitle: String?
    let sourceTitle: String?
    let sourceCandidateID: String?
    let sourceImportJobID: String?
    let targetSeasonID: String?
    let requestedBy: String
    let errorMessage: String?
    let assetRetryStatus: SeasonAssetRetryStatus?
    let assetCompletedCount: Int?
    let assetFailedCount: Int?
    let reviewStatus: SeasonImportReviewStatus?
    let reviewGeneration: Int?
    let repairStatus: SeasonRepairStatus?
    let repairGeneration: Int?
    let extractionQualityReasons: [String]?
    let createdAt: Timestamp?
    let updatedAt: Timestamp?

    func toDomain(documentID: String) throws -> SeasonImportJob {
        guard !documentID.isEmpty else { throw MappingError.missingDocumentID }
        guard !brandID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MappingError.missingRequiredField("brandID")
        }

        return SeasonImportJob(
            id: documentID,
            brandID: BrandID(value: brandID),
            jobType: jobType,
            status: status,
            phase: phase,
            sourceURL: sourceURL,
            seasonTitle: seasonTitle,
            sourceTitle: sourceTitle,
            sourceCandidateID: sourceCandidateID,
            sourceImportJobID: sourceImportJobID,
            targetSeasonID: targetSeasonID.map { SeasonID(value: $0) },
            requestedBy: requestedBy,
            errorMessage: errorMessage,
            assetRetryStatus: assetRetryStatus,
            assetCompletedCount: assetCompletedCount ?? 0,
            assetFailedCount: assetFailedCount ?? 0,
            reviewStatus: reviewStatus,
            reviewGeneration: reviewGeneration ?? 0,
            repairStatus: repairStatus,
            repairGeneration: repairGeneration ?? 0,
            extractionQualityReasons: extractionQualityReasons ?? [],
            createdAt: createdAt?.dateValue() ?? Date(timeIntervalSince1970: 0),
            updatedAt: updatedAt?.dateValue() ?? Date(timeIntervalSince1970: 0)
        )
    }
}
