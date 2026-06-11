//
//  SeasonImportBatchRequestResult.swift
//  OutPick
//
//  Created by Codex on 4/23/26.
//

import Foundation

struct SeasonImportBatchFailure: Equatable {
    let candidateID: String
    let title: String?
    let errorMessage: String
}

struct SeasonImportBatchRequestResult: Equatable {
    let brandID: BrandID
    let candidateIDs: [String]
    let jobIDs: [String]
    let requestedJobCount: Int
    let requestedImportJobCount: Int
    let createdJobCount: Int
    let duplicateJobCount: Int
    let failedJobCount: Int
    let skippedJobCount: Int
    let failedCandidates: [SeasonImportBatchFailure]
}
