//
//  SeasonImportExtractionProgress.swift
//  OutPick
//
//  Created by Codex on 4/24/26.
//

import Foundation

struct SeasonImportExtractionProgress: Equatable {
    enum ItemStatus: Equatable {
        case queued
        case processing
        case retryWaiting
        case succeeded
        case awaitingReview
        case failed
        case skipped
        case duplicate
        case recoveryRequired

        var isTerminal: Bool {
            switch self {
            case .succeeded, .awaitingReview, .failed, .skipped, .duplicate:
                return true
            case .queued, .processing, .retryWaiting, .recoveryRequired:
                return false
            }
        }
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
    let batchState: LookbookImportQueueContract.BatchState?
    let stateRevision: Int64?

    var isFinished: Bool {
        totalCount > 0 && (
            completedCount >= totalCount || batchState == .recoveryRequired || batchState == .released
        )
    }

    var reviewRequiredCount: Int { items.filter { $0.status == .awaitingReview }.count }
    var recoveryRequiredCount: Int { items.filter { $0.status == .recoveryRequired }.count }
}
