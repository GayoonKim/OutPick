//
//  SeasonImportJob.swift
//  OutPick
//
//  Created by Codex on 4/23/26.
//

import Foundation

enum SeasonImportJobType: String, Codable, Equatable {
    case importSeasonFromURL
}

enum SeasonImportJobStatus: String, Codable, CaseIterable, Equatable {
    case queued
    case running
    case parsed
    case success
    case failed

    var blocksDuplicateImportRequest: Bool {
        switch self {
        case .queued, .running, .parsed, .success:
            return true
        case .failed:
            return false
        }
    }

    var isSeasonReadyFlowFinished: Bool {
        switch self {
        case .success, .failed:
            return true
        case .queued, .running, .parsed:
            return false
        }
    }
}

struct SeasonImportJob: Equatable, Identifiable, Codable {
    let id: String
    let brandID: BrandID
    let jobType: SeasonImportJobType
    let status: SeasonImportJobStatus
    let sourceURL: String
    let sourceCandidateID: String?
    let requestedBy: String
    let errorMessage: String?
    let createdAt: Date
    let updatedAt: Date
}
