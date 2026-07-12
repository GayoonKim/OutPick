//
//  LookbookDeletionRequest.swift
//  OutPick
//
//  Created by Codex on 7/7/26.
//

import Foundation

enum LookbookDeletionTargetType: String, Codable, CaseIterable, Equatable, Identifiable {
    case brand
    case season
    case post

    var id: String { rawValue }

    var title: String {
        switch self {
        case .brand: return "브랜드"
        case .season: return "시즌"
        case .post: return "포스트"
        }
    }
}

enum LookbookDeletionRequestStatus: String, Codable, CaseIterable, Equatable, Identifiable {
    case active
    case cancelled
    case restored
    case purged
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: return "진행 중"
        case .cancelled: return "취소됨"
        case .restored: return "복구됨"
        case .purged: return "삭제 완료"
        case .failed: return "처리 실패"
        }
    }
}

enum LookbookDeletionManualRetryState: String, Codable, Equatable {
    case queued
    case running
    case failed
}

struct LookbookDeletionRequest: Equatable, Identifiable {
    let requestID: String
    let targetType: LookbookDeletionTargetType
    let targetID: String
    let targetPath: String
    let brandID: BrandID
    let seasonID: SeasonID?
    let postID: PostID?
    let status: LookbookDeletionRequestStatus
    let requestedBy: UserID
    let requestedAt: Date?
    let restoreUntil: Date?
    let purgeAfter: Date?
    let reason: String?
    let cancelledBy: UserID?
    let cancelledAt: Date?
    let restoredBy: UserID?
    let restoredAt: Date?
    let updatedBy: UserID?
    let updatedAt: Date?
    let targetDisplayName: String?
    let targetImagePath: String?
    let brandName: String?
    let brandEnglishName: String?
    let brandLogoThumbPath: String?
    let seasonTitle: String?
    let seasonCoverThumbPath: String?
    let postCaption: String?
    let postImageThumbPath: String?
    let autoRetryEligible: Bool
    let retryAfter: Date?
    let purgeAttemptCount: Int
    let purgeErrorMessage: String?
    let manualRetryState: LookbookDeletionManualRetryState?
    let manualRetryCount: Int
    let purgeInProgress: Bool

    var id: String { requestID }

    var isPurgeRetryInProgress: Bool {
        purgeInProgress || manualRetryState == .queued || manualRetryState == .running
    }

    var isPurgeRetryPendingOrInProgress: Bool {
        autoRetryEligible || isPurgeRetryInProgress
    }
}

struct LookbookDeletionRetryReceipt: Equatable {
    let requestID: String
    let manualRetryState: LookbookDeletionManualRetryState
    let duplicate: Bool
}

struct LookbookDeletionRequestPage {
    struct Cursor: Equatable {
        let updatedAt: String
        let requestID: String
    }

    let requests: [LookbookDeletionRequest]
    let nextCursor: Cursor?
}

struct LookbookDeletionMutationReceipt: Equatable {
    let brandID: BrandID
    let seasonID: SeasonID?
    let postID: PostID?
    let requestID: String?
    let status: String
    let duplicate: Bool
    let cancelled: Bool
    let restored: Bool
}

struct LookbookDeletionBatchResult: Equatable {
    let brandID: BrandID
    let targetType: LookbookDeletionTargetType
    let requestedCount: Int
    let succeededCount: Int
    let failedCount: Int
    let results: [LookbookDeletionBatchItemResult]
}

struct LookbookDeletionBatchItemResult: Equatable, Identifiable {
    let success: Bool
    let targetType: LookbookDeletionTargetType
    let targetID: String
    let brandID: BrandID
    let seasonID: SeasonID?
    let postID: PostID?
    let requestID: String?
    let status: String?
    let duplicate: Bool
    let code: String?
    let message: String?

    var id: String {
        [
            targetType.rawValue,
            brandID.value,
            seasonID?.value,
            postID?.value,
            targetID
        ]
            .compactMap { $0 }
            .joined(separator: ":")
    }
}
