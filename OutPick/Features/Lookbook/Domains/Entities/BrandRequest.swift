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
            return "요청 접수"
        case .reviewing:
            return "처리 중"
        case .added:
            return "등록 완료"
        case .rejected:
            return "보류"
        }
    }
}

enum BrandRequestListScope: String, Codable, CaseIterable, Equatable {
    case active
    case history
}

enum BrandRequestFailure: LocalizedError, Equatable {
    case invalidInput, invalidCursor, dailyLimit, requestBlocked, unauthenticated
    case permissionDenied, queryBudget, invalidStoredData, unavailable

    var errorDescription: String? {
        switch self {
        case .invalidInput: return "브랜드명과 공식 URL을 확인해 주세요."
        case .invalidCursor: return "요청 내역을 새로 불러온 뒤 다시 시도해 주세요."
        case .dailyLimit: return "오늘 요청 가능 횟수를 모두 사용했어요."
        case .requestBlocked: return "브랜드 요청이 제한된 계정이에요."
        case .unauthenticated: return "로그인 상태를 확인한 뒤 다시 시도해 주세요."
        case .permissionDenied: return "요청을 확인할 권한이 없어요. 로그인 상태를 확인해 주세요."
        case .queryBudget: return "요청 내역을 한 번에 불러오지 못했어요. 잠시 후 다시 시도해 주세요."
        case .invalidStoredData: return "요청 정보를 확인하지 못했어요. 잠시 후 다시 시도해 주세요."
        case .unavailable: return "서버에 연결하지 못했어요. 잠시 후 다시 시도해 주세요."
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
    var resolvedBrandID: BrandID? = nil

    var destinationBrandID: BrandID? {
        status == .added ? resolvedBrandID : nil
    }
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

