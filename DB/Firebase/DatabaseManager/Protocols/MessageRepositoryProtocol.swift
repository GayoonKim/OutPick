//
//  MessageRepositoryProtocol.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation
import FirebaseFirestore

/// 메시지 관련 데이터베이스 작업을 위한 프로토콜
protocol MessageRepositoryProtocol {
    /// 메시지 저장
    func saveMessage(_ message: ChatMessage, _ room: ChatRoom) async throws
    
    /// 삭제된 메시지 감지 리스너
    func listenToDeletedMessages(roomID: String, onDeleted: @escaping (String) -> Void) -> ListenerRegistration
    
    /// 메시지 삭제 상태 업데이트
    func updateMessageIsDeleted(roomID: String, messageID: String) async throws
    
    /// 여러 메시지의 삭제 상태 일괄 조회
    func fetchDeletionStates(roomID: String, messageIDs: [String]) async throws -> [String: Bool]
    
    /// 메시지 페이지네이션 조회
    func fetchMessagesPaged(for room: ChatRoom, pageSize: Int, reset: Bool) async throws -> [ChatMessage]
    
    /// 특정 메시지 이전의 과거 메시지 조회
    func fetchOlderMessages(for room: ChatRoom, before messageID: String, limit: Int) async throws -> [ChatMessage]
    
    /// 특정 메시지 이후의 최신 메시지 조회
    func fetchMessagesAfter(room: ChatRoom, after messageID: String, limit: Int) async throws -> [ChatMessage]
}

