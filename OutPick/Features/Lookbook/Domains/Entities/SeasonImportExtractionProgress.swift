//
//  SeasonImportExtractionProgress.swift
//  OutPick
//
//  Created by Codex on 4/24/26.
//

import Foundation

struct SeasonImportExtractionProgress: Equatable {
    enum ItemStatus: Equatable {
        case processing
        case succeeded
        case failed
    }

    struct Item: Equatable, Identifiable {
        let candidateID: String
        let jobID: String?
        let status: ItemStatus

        var id: String { candidateID }
    }

    let totalCount: Int
    let matchedJobCount: Int
    let completedCount: Int
    let failedCount: Int
    let items: [Item]

    var isFinished: Bool {
        totalCount > 0 && completedCount >= totalCount
    }
}
