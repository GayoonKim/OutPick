//
//  SeasonImportBatchProcessResult.swift
//  OutPick
//
//  Created by Codex on 4/23/26.
//

import Foundation

struct SeasonImportBatchProcessResult: Equatable {
    let brandID: BrandID
    let candidateIDs: [String]
    let jobIDs: [String]
    let requestedJobCount: Int
    let duplicateJobCount: Int
    let processedJobCount: Int
    let failedJobCount: Int
    let skippedJobCount: Int
}
