//
//  SeasonImportRequestReceipt.swift
//  OutPick
//
//  Created by Codex on 4/23/26.
//

import Foundation

struct SeasonImportRequestReceipt: Equatable {
    let jobID: String
    let status: String
    let normalizedSeasonURL: String
    let sourceCandidateID: String?
    let isDuplicate: Bool
}
