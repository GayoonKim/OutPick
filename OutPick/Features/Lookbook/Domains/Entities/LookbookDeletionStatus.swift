//
//  LookbookDeletionStatus.swift
//  OutPick
//
//  Created by Codex on 7/7/26.
//

import Foundation

enum BrandDeletionStatus: String, Codable, Equatable {
    case active
    case deletionRequested
}

enum ContentDeletionStatus: String, Codable, Equatable {
    case active
    case deleted
}

enum LookbookContentUnavailableError: LocalizedError {
    case brandUnavailable
    case seasonUnavailable
    case postUnavailable

    var errorDescription: String? {
        switch self {
        case .brandUnavailable:
            return "이 브랜드는 더 이상 볼 수 없습니다."
        case .seasonUnavailable:
            return "이 시즌은 더 이상 볼 수 없습니다."
        case .postUnavailable:
            return "이 포스트는 더 이상 볼 수 없습니다."
        }
    }
}
