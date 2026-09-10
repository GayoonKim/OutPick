//
//  FirebaseMessageRepositoryProtocol.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation

/// 메시지 관련 데이터베이스 작업을 위한 프로토콜
protocol FirebaseMessageRepositoryProtocol {
    func fetchConfirmedMessage(roomID: String, messageID: String) async throws -> ChatMessage?
    func fetchMessageDeletionRevision(roomID: String) async throws -> Int64
    func fetchDeletionDeltas(roomID: String, afterRevision: Int64, limit: Int) async throws -> [ChatDeletionDelta]
    func fetchDeletionDeltas(roomID: String, messageIDs: [String]) async throws -> [ChatDeletionDelta]

    /// 메시지 페이지네이션 조회
    func fetchMessagesPaged(for room: ChatRoom, pageSize: Int, reset: Bool) async throws -> [ChatMessage]

    /// 최신 메시지 tail 조회
    func fetchLatestMessages(for room: ChatRoom, limit: Int) async throws -> [ChatMessage]

    /// 특정 seq 이후의 메시지 조회
    func fetchMessagesAfterSeq(room: ChatRoom, afterSeq: Int64, limit: Int) async throws -> [ChatMessage]

    /// 특정 seq 이전의 메시지 조회
    func fetchMessagesBeforeSeq(room: ChatRoom, beforeSeq: Int64, limit: Int) async throws -> [ChatMessage]
    
    /// 특정 메시지 이전의 과거 메시지 조회
    func fetchOlderMessages(for room: ChatRoom, before messageID: String, limit: Int) async throws -> [ChatMessage]
    
    /// 특정 메시지 이후의 최신 메시지 조회
    func fetchMessagesAfter(room: ChatRoom, after messageID: String, limit: Int) async throws -> [ChatMessage]

    /// 서버 인덱스 기반 방 전체 메시지 검색 (추후 백엔드 검색 API 연동)
    func searchMessagesInRoom(roomID: String, keyword: String) async throws -> ChatMessageServerSearchResponse
}

extension FirebaseMessageRepositoryProtocol {
    func fetchConfirmedMessage(roomID: String, messageID: String) async throws -> ChatMessage? {
        throw ChatMediaUploadError.invalidUploadContract
    }

    func fetchMessageDeletionRevision(roomID: String) async throws -> Int64 {
        throw ChatDeletionSyncError.invalidHead
    }

    func fetchDeletionDeltas(roomID: String, afterRevision: Int64, limit: Int) async throws -> [ChatDeletionDelta] {
        throw ChatDeletionSyncError.invalidHead
    }

    func fetchDeletionDeltas(roomID: String, messageIDs: [String]) async throws -> [ChatDeletionDelta] {
        throw ChatDeletionSyncError.invalidHead
    }
}
