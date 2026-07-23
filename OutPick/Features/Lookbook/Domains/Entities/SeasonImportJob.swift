//
//  SeasonImportJob.swift
//  OutPick
//
//  Created by Codex on 4/23/26.
//

import Foundation

enum SeasonImportJobType: String, Codable, Equatable {
    case importSeasonFromURL
    case retrySeasonAssets
}

enum SeasonImportJobStatus: String, Codable, CaseIterable, Equatable {
    case queued
    case processing
    case awaitingReview
    case succeeded
    case partialFailed
    case failed
    case cancelled

    var blocksDuplicateImportRequest: Bool {
        switch self {
        case .queued, .processing, .awaitingReview, .succeeded, .partialFailed:
            return true
        case .failed, .cancelled:
            return false
        }
    }

    var isSeasonReadyFlowFinished: Bool {
        switch self {
        case .succeeded, .partialFailed, .failed, .cancelled:
            return true
        case .queued, .processing, .awaitingReview:
            return false
        }
    }

    var isFailed: Bool {
        switch self {
        case .partialFailed, .failed:
            return true
        case .queued, .processing, .awaitingReview, .succeeded, .cancelled:
            return false
        }
    }
}

enum SeasonImportJobPhase: String, Codable, Equatable {
    case dispatching
    case parsing
    case reviewing
    case materializing
    case syncingAssets
    case completed
}

enum SeasonImportReviewStatus: String, Codable, Equatable {
    case pending
    case correctionRequired
    case reanalyzing
    case repairPreviewReady
    case approved
}

enum SeasonRepairStatus: String, Codable, Equatable {
    case analyzing
    case previewReady
    case noChanges
    case applying
    case applied
    case failed
}

enum SeasonAssetRetryStatus: String, Codable, Equatable {
    case queued
    case processing
    case succeeded
    case failed

    var isInFlight: Bool {
        switch self {
        case .queued, .processing:
            return true
        case .succeeded, .failed:
            return false
        }
    }
}

struct SeasonImportJob: Equatable, Identifiable, Codable {
    let id: String
    let brandID: BrandID
    let jobType: SeasonImportJobType
    let status: SeasonImportJobStatus
    let phase: SeasonImportJobPhase
    let sourceURL: String
    let seasonTitle: String?
    let sourceTitle: String?
    let sourceCandidateID: String?
    let sourceImportJobID: String?
    let targetSeasonID: SeasonID?
    let requestedBy: String
    let errorMessage: String?
    let assetRetryStatus: SeasonAssetRetryStatus?
    let assetCompletedCount: Int
    let assetFailedCount: Int
    let reviewStatus: SeasonImportReviewStatus?
    let reviewGeneration: Int
    let repairStatus: SeasonRepairStatus?
    let repairGeneration: Int
    let extractionQualityReasons: [String]
    let createdAt: Date
    let updatedAt: Date

    var canRetryAssets: Bool {
        jobType == .importSeasonFromURL
        && targetSeasonID != nil
        && assetFailedCount > 0
        && (status == .partialFailed || status == .failed)
        && assetRetryStatus?.isInFlight != true
    }

    var isAssetRetryInFlight: Bool {
        assetRetryStatus?.isInFlight == true
    }

    var needsExtractionReview: Bool {
        status == .awaitingReview && repairStatus != .previewReady
    }

    var canRequestSeasonRepair: Bool {
        jobType == .importSeasonFromURL
        && targetSeasonID != nil
        && (status == .succeeded || status == .partialFailed || status == .failed)
        && repairStatus != .applying
    }

    var needsSeasonRepairPreview: Bool {
        status == .awaitingReview && repairStatus == .previewReady
    }

    var displayTitle: String {
        for title in [seasonTitle, sourceTitle] {
            if let title, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                return title
            }
        }
        return "시즌 가져오기"
    }
}
