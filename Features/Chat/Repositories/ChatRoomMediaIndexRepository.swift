//
//  ChatRoomMediaIndexRepository.swift
//  OutPick
//
//  Created by Codex on 3/7/26.
//

import Foundation

protocol ChatRoomMediaIndexRepositoryProtocol {
    func countImageIndex(inRoom roomID: String) throws -> Int
    func countVideoIndex(inRoom roomID: String) throws -> Int
    func fetchLatestImageIndex(inRoom roomID: String, limit: Int) throws -> [ImageIndexMeta]
    func fetchLatestVideoIndex(inRoom roomID: String, limit: Int) throws -> [VideoIndexMeta]
    func fetchOlderImageIndex(
        inRoom roomID: String,
        beforeSentAt: Date,
        beforeMessageID: String,
        limit: Int
    ) throws -> [ImageIndexMeta]
    func fetchOlderVideoIndex(
        inRoom roomID: String,
        beforeSentAt: Date,
        beforeMessageID: String,
        limit: Int
    ) throws -> [VideoIndexMeta]
    func upsertMediaIndexEntries(_ entries: [ChatRoomMediaIndexEntry]) throws
}

final class GRDBChatRoomMediaIndexRepository: ChatRoomMediaIndexRepositoryProtocol {
    private let grdbManager: GRDBManager

    init(grdbManager: GRDBManager = .shared) {
        self.grdbManager = grdbManager
    }

    func countImageIndex(inRoom roomID: String) throws -> Int {
        try grdbManager.countImageIndex(inRoom: roomID)
    }

    func countVideoIndex(inRoom roomID: String) throws -> Int {
        try grdbManager.countVideoIndex(inRoom: roomID)
    }

    func fetchLatestImageIndex(inRoom roomID: String, limit: Int) throws -> [ImageIndexMeta] {
        try grdbManager.fetchLatestImageIndex(inRoom: roomID, limit: limit)
    }

    func fetchLatestVideoIndex(inRoom roomID: String, limit: Int) throws -> [VideoIndexMeta] {
        try grdbManager.fetchLatestVideoIndex(inRoom: roomID, limit: limit)
    }

    func fetchOlderImageIndex(
        inRoom roomID: String,
        beforeSentAt: Date,
        beforeMessageID: String,
        limit: Int
    ) throws -> [ImageIndexMeta] {
        try grdbManager.fetchOlderImageIndex(
            inRoom: roomID,
            beforeSentAt: beforeSentAt,
            beforeMessageID: beforeMessageID,
            limit: limit
        )
    }

    func fetchOlderVideoIndex(
        inRoom roomID: String,
        beforeSentAt: Date,
        beforeMessageID: String,
        limit: Int
    ) throws -> [VideoIndexMeta] {
        try grdbManager.fetchOlderVideoIndex(
            inRoom: roomID,
            beforeSentAt: beforeSentAt,
            beforeMessageID: beforeMessageID,
            limit: limit
        )
    }

    func upsertMediaIndexEntries(_ entries: [ChatRoomMediaIndexEntry]) throws {
        try grdbManager.upsertMediaIndexEntries(entries)
    }
}
