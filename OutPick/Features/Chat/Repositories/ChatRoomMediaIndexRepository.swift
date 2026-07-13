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
