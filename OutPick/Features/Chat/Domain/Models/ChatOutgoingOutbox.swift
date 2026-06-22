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
    case uploaded
    case sending
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
}

struct ChatOutgoingOutboxImagePayload: Codable, Equatable, Sendable {
    struct Item: Codable, Equatable, Sendable {
        let index: Int
        let originalFilePath: String
        let thumbFilePath: String
        let originalWidth: Int
        let originalHeight: Int
        let bytesOriginal: Int
        let sha256: String
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
}

struct ChatOutgoingOutboxUploadedImagesPayload: Codable, Equatable, Sendable {
    let attachments: [Attachment]
}
