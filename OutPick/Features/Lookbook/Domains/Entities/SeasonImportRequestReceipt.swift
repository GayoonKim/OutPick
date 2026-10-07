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
    let requestID: String?
    let batchID: String?

    init(
        jobID: String,
        status: String,
        normalizedSeasonURL: String,
        sourceCandidateID: String?,
        isDuplicate: Bool,
        requestID: String? = nil,
        batchID: String? = nil
    ) {
        self.jobID = jobID
        self.status = status
        self.normalizedSeasonURL = normalizedSeasonURL
        self.sourceCandidateID = sourceCandidateID
        self.isDuplicate = isDuplicate
        self.requestID = requestID
        self.batchID = batchID
    }
}
