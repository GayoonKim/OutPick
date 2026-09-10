//
//  ChatOutgoingOutbox.swift
//  OutPick
//
//  Created by Codex on 6/23/26.
//

import Foundation

enum ChatOutgoingOutboxKind: String, Codable, Equatable, Sendable {
    case text
    case images
    case video
}

enum ChatOutgoingOutboxStage: String, Codable, Equatable, Sendable {
    case needsUpload
    case uploading
    case uploaded
    case queued
    case processing
    case sending
    case canceled
    case expired
    case failed
}

struct ChatOutgoingOutboxRecord: Codable, Equatable, Sendable {
    let messageID: String
    let roomID: String
    let kind: ChatOutgoingOutboxKind
    var stage: ChatOutgoingOutboxStage
    let createdAt: Date
    var updatedAt: Date
    var localPayloadJSON: String?
    var uploadedPayloadJSON: String?
    var lastError: String?
    var uploadID: String? = nil
    var clientMutationID: String? = nil
    var processingStatus: String? = nil
    var statusCheckedAt: Date? = nil
    var terminalAt: Date? = nil
    var expiresAt: Date? = nil
    var sessionPayloadJSON: String? = nil

    var requiresManualMediaRetryAfterRestore: Bool {
        switch stage {
        case .needsUpload, .uploaded, .failed:
            return true
        case .uploading, .queued, .processing, .sending, .canceled, .expired:
            return false
        }
    }
}

struct ChatOutgoingOutboxImagePayload: Codable, Equatable, Sendable {
    struct Item: Codable, Equatable, Sendable {
        private enum CodingKeys: String, CodingKey {
            case index, originalFilePath, thumbFilePath, originalWidth, originalHeight
            case bytesOriginal, sha256, contentType, mediaFormat, isAnimated, preparationVersion
        }
        let index: Int
        let originalFilePath: String
        let thumbFilePath: String
        let originalWidth: Int
        let originalHeight: Int
        let bytesOriginal: Int
        let sha256: String
        let contentType: String
        let mediaFormat: String
        let isAnimated: Bool
        let preparationVersion: Int

        init(
            index: Int,
            originalFilePath: String,
            thumbFilePath: String,
            originalWidth: Int,
            originalHeight: Int,
            bytesOriginal: Int,
            sha256: String,
            contentType: String = "image/jpeg",
            mediaFormat: String = "jpeg",
            isAnimated: Bool = false,
            preparationVersion: Int = 3
        ) {
            self.index = index
            self.originalFilePath = originalFilePath
            self.thumbFilePath = thumbFilePath
            self.originalWidth = originalWidth
            self.originalHeight = originalHeight
            self.bytesOriginal = bytesOriginal
            self.sha256 = sha256
            self.contentType = contentType
            self.mediaFormat = mediaFormat
            self.isAnimated = isAnimated
            self.preparationVersion = preparationVersion
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            index = try values.decode(Int.self, forKey: .index)
            originalFilePath = try values.decode(String.self, forKey: .originalFilePath)
            thumbFilePath = try values.decode(String.self, forKey: .thumbFilePath)
            originalWidth = try values.decode(Int.self, forKey: .originalWidth)
            originalHeight = try values.decode(Int.self, forKey: .originalHeight)
            bytesOriginal = try values.decode(Int.self, forKey: .bytesOriginal)
            sha256 = try values.decode(String.self, forKey: .sha256)
            contentType = try values.decodeIfPresent(String.self, forKey: .contentType) ?? "image/jpeg"
            mediaFormat = try values.decodeIfPresent(String.self, forKey: .mediaFormat) ?? "jpeg"
            isAnimated = try values.decodeIfPresent(Bool.self, forKey: .isAnimated) ?? false
            preparationVersion = try values.decodeIfPresent(Int.self, forKey: .preparationVersion) ?? 0
        }
    }

    let items: [Item]
}

struct ChatOutgoingOutboxVideoPayload: Codable, Equatable, Sendable {
    let compressedFilePath: String
    let thumbnailFilePath: String
    let sha256: String
    let duration: Double
    let width: Int
    let height: Int
    let sizeBytes: Int64
    let approxBitrateMbps: Double
    let preset: String
    var preparationVersion: Int? = nil
}

struct ChatOutgoingOutboxUploadedImagesPayload: Codable, Equatable, Sendable {
    let attachments: [Attachment]
}

struct ChatMediaUploadSessionPayload: Codable, Equatable, Sendable {
    let uploadID: String
    let clientMutationID: String
    let kind: String
    let expiresAt: Date
}
