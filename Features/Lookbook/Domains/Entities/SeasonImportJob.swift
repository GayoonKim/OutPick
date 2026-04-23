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
    case success
    case failed
}

struct SeasonImportJob: Equatable, Identifiable, Codable {
    let id: String
    let brandID: BrandID
    let jobType: SeasonImportJobType
    let status: SeasonImportJobStatus
    let sourceURL: String
    let requestedBy: String
    let errorMessage: String?
    let createdAt: Date
    let updatedAt: Date
}
