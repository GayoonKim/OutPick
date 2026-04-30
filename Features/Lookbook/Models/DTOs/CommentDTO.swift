//
//  CommentDTO.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation
import FirebaseFirestore

struct CommentAttachmentDTO: Codable {
    let id: String?
    let type: String
    let remoteURL: String?
    let thumbPath: String?
    let detailPath: String?
    let originalPath: String?

    func toDomain() throws -> CommentAttachment {
        guard let normalizedID else {
            throw MappingError.missingRequiredField("attachment.id")
        }
        guard let mediaType = MediaType(rawValue: type) else {
            throw MappingError.invalidEnumValue(type)
        }

        let normalizedRemoteURL = try remoteURL.flatMap { rawValue -> URL? in
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { return nil }
            guard let url = URL(string: trimmed) else {
                throw MappingError.invalidURL(rawValue)
            }
            return url
        }
        let normalizedThumbPath = normalizedNonEmpty(thumbPath)
        let normalizedDetailPath = normalizedNonEmpty(detailPath)
        let normalizedOriginalPath = normalizedNonEmpty(originalPath)

        guard
            normalizedRemoteURL != nil ||
                normalizedThumbPath != nil ||
                normalizedDetailPath != nil ||
                normalizedOriginalPath != nil
        else {
            throw MappingError.missingRequiredField("attachment.path")
        }

        return CommentAttachment(
            id: normalizedID,
            type: mediaType,
            remoteURL: normalizedRemoteURL,
            thumbPath: normalizedThumbPath,
            detailPath: normalizedDetailPath,
            originalPath: normalizedOriginalPath
        )
    }

    private var normalizedID: String? {
        normalizedNonEmpty(id)
    }

    private func normalizedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct CommentDTO: Codable {
    @DocumentID var id: String?

    /// comments가 `posts/{postId}/comments/{commentId}`라면 postID는 경로에서 주입 추천
    let postID: String?

    let userID: String?
    let createdBy: String?
    let message: String
    let createdAt: Timestamp?
    let updatedAt: Timestamp?
    let isDeleted: Bool?
    let likeCount: Int?
    let replyCount: Int?
    let isPinned: Bool?
    let pinnedAt: Timestamp?
    let pinnedBy: String?
    let parentCommentID: String?
    let attachments: [CommentAttachmentDTO]?

    func toDomain(postID: PostID) throws -> Comment {
        guard let id else { throw MappingError.missingDocumentID }
        guard let authorID = normalizedUserID else {
            throw MappingError.missingRequiredField("userID")
        }
        let domainAttachments = try (attachments ?? []).map { try $0.toDomain() }

        return Comment(
            id: CommentID(value: id),
            postID: postID,
            userID: UserID(value: authorID),
            message: message,
            createdAt: createdAt?.dateValue() ?? Date(timeIntervalSince1970: 0),
            isDeleted: isDeleted ?? false,
            likeCount: max(0, likeCount ?? 0),
            replyCount: max(0, replyCount ?? 0),
            isPinned: isPinned ?? false,
            pinnedAt: pinnedAt?.dateValue(),
            pinnedBy: normalizedPinnedBy.map { UserID(value: $0) },
            parentCommentID: normalizedParentCommentID.map { CommentID(value: $0) },
            attachments: domainAttachments
        )
    }

    /// 선택: 문서에 postID가 포함된 경우
    func toDomainFromEmbeddedPostID() throws -> Comment {
        guard let embeddedPostID = postID, !embeddedPostID.isEmpty else {
            throw MappingError.missingRequiredField("postID")
        }
        return try toDomain(postID: PostID(value: embeddedPostID))
    }

    private var normalizedUserID: String? {
        normalizedNonEmpty(userID) ?? normalizedNonEmpty(createdBy)
    }

    private var normalizedPinnedBy: String? {
        normalizedNonEmpty(pinnedBy)
    }

    private var normalizedParentCommentID: String? {
        normalizedNonEmpty(parentCommentID)
    }

    private func normalizedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
