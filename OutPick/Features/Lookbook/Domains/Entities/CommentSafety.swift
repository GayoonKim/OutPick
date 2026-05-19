//
//  CommentSafety.swift
//  OutPick
//
//  Created by Codex on 5/6/26.
//

import Foundation

enum CommentSafetyTargetType: String, Codable, Hashable {
    case comment
    case reply
}

enum CommentReportReason: String, CaseIterable, Codable, Hashable {
    case spam
    case harassment
    case sexualContent
    case illegalOrDangerous
    case personalInformation
    case other

    var title: String {
        switch self {
        case .spam:
            return "스팸"
        case .harassment:
            return "혐오/괴롭힘"
        case .sexualContent:
            return "성적 콘텐츠"
        case .illegalOrDangerous:
            return "불법/위험"
        case .personalInformation:
            return "개인정보 노출"
        case .other:
            return "기타"
        }
    }
}

enum CommentReportStatus: String, Codable, Hashable {
    case pending
    case reviewed
    case rejected
    case actioned
}

enum UserBlockSource: String, Codable, Hashable {
    case comment
    case reply
    case profile
}

struct CommentReportTarget: Codable, Hashable {
    var targetType: CommentSafetyTargetType
    var brandID: BrandID
    var seasonID: SeasonID
    var postID: PostID
    var commentID: CommentID
    var parentCommentID: CommentID?
    var authorID: UserID
    var contentSnapshot: String
    var authorNicknameSnapshot: String?
}

struct CommentReport: Codable, Equatable, Identifiable {
    var id: CommentReportID
    var reporterUserID: UserID
    var target: CommentReportTarget
    var reason: CommentReportReason
    var detail: String?
    var status: CommentReportStatus
    var createdAt: Date
}

struct UserBlock: Codable, Equatable, Identifiable {
    var blockerUserID: UserID
    var blockedUserID: UserID
    var blockedUserNicknameSnapshot: String?
    var source: UserBlockSource
    var createdAt: Date

    var id: UserID {
        blockedUserID
    }
}
