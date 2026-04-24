//
//  SeasonImportProcessResult.swift
//  OutPick
//
//  Created by Codex on 4/23/26.
//

import Foundation

struct SeasonImportProcessResult: Equatable {
    let processed: Bool
    let reason: String?
    let brandID: BrandID?
    let jobID: String?
    let sourceURL: String?
    let imageCandidateCount: Int?
}
