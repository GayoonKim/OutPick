//
//  SeasonImportExtractionProgress.swift
//  OutPick
//
//  Created by Codex on 4/24/26.
//

import Foundation

struct SeasonImportExtractionProgress: Equatable {
    let totalCount: Int
    let matchedJobCount: Int
    let completedCount: Int
    let failedCount: Int

    var isFinished: Bool {
        totalCount > 0 && completedCount >= totalCount
    }
}
