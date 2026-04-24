//
//  SeasonCandidate.swift
//  OutPick
//
//  Created by Codex on 4/23/26.
//

import Foundation

struct SeasonCandidate: Equatable, Identifiable, Codable {
    let id: String
    let brandID: BrandID
    let title: String
    let seasonURL: String
    let coverImageURL: String?
    let sourceArchiveURL: String
    let extractionScore: Double
    let sortIndex: Int
    let status: String
    let createdAt: Date
    let updatedAt: Date
}
