//
//  BrandRequest.swift
//  OutPick
//
//  Created by Codex on 7/6/26.
//

import Foundation

enum BrandRequestStatus: String, Codable, CaseIterable, Equatable {
    case submitted
    case reviewing
    case added
    case rejected

    var displayTitle: String {
        switch self {
        case .submitted:
            return "접수됨"
        case .reviewing:
            return "검토 중"
        case .added:
            return "추가됨"
        case .rejected:
            return "보류"
        }
    }
}

enum BrandRequestListScope: String, Codable, CaseIterable, Equatable {
    case active
    case history
}

enum BrandRequestAdminStage: String, Codable, CaseIterable, Equatable {
    case requested
    case processing
    case completed
    case rejected

    var displayTitle: String {
        switch self {
        case .requested:
            return "요청됨"
        case .processing:
            return "처리 중"
        case .completed:
            return "완료"
        case .rejected:
            return "보류"
        }
    }
}

enum BrandRequestRejectionReason: String, Codable, CaseIterable, Equatable {
    case unavailable
    case spam
    case other

    var displayTitle: String {
        switch self {
        case .unavailable:
            return "룩북 확인 불가"
        case .spam:
            return "스팸"
        case .other:
            return "기타"
        }
    }
}

struct BrandRequest: Identifiable, Equatable {
    let id: String
    let brandName: String
    let normalizedBrandName: String
    let englishBrandName: String?
    let normalizedEnglishBrandName: String?
    let groupID: String?
    let dedupeKey: String?
    let dedupeKeySource: String?
    let status: BrandRequestStatus
    let resolvedBrandID: BrandID?
    let rejectionReason: String?
    let createdAt: Date?
    let updatedAt: Date?
}

struct BrandRequestSubmissionReceipt: Equatable {
    let requestID: String
    let groupID: String?
    let status: BrandRequestStatus
    let isDuplicate: Bool
    let remainingToday: Int
}

struct BrandRequestPage: Equatable {
    struct Cursor: Equatable {
        let createdAt: String
        let requestID: String
    }

    let requests: [BrandRequest]
    let nextCursor: Cursor?
    let scope: BrandRequestListScope
}

struct AdminBrandRequestGroup: Identifiable, Equatable {
    let id: String
    let dedupeKey: String
    let dedupeKeySource: String
    let displayNameSnapshot: String
    let normalizedBrandName: String
    let englishBrandName: String?
    let normalizedEnglishBrandName: String?
    let requestCount: Int
    let adminStage: BrandRequestAdminStage
    let status: BrandRequestStatus
    let rejectionReason: BrandRequestRejectionReason?
    let resolvedBrandID: BrandID?
    let createdBrandID: BrandID?
    let brandCreatedAt: Date?
    let brandCreatedBy: String?
    let adminNote: String?
    let lastRequestID: String?
    let lastRequestedAt: Date?
    let createdAt: Date?
    let updatedAt: Date?
    let reviewedAt: Date?
    let resolvedAt: Date?
    let rejectedAt: Date?
}

struct AdminBrandRequestGroupPage: Equatable {
    struct Cursor: Equatable {
        let updatedAt: String
        let groupID: String
    }

    let groups: [AdminBrandRequestGroup]
    let nextCursor: Cursor?
}

struct AdminBrandRequestGroupStageUpdateReceipt: Equatable {
    let groupID: String
    let status: BrandRequestStatus
    let adminStage: BrandRequestAdminStage
    let updatedRequestCount: Int
}
