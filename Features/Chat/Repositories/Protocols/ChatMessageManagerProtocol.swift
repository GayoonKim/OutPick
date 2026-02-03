//
//  ChatMessageManagerProtocol.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation
import Combine

/// 메시지 관리 관련 비즈니스 로직을 위한 프로토콜
protocol ChatMessageManagerProtocol {
    /// 초기 메시지 로드
    func loadInitialMessages(room: ChatRoom, isParticipant: Bool) async throws -> (local: [ChatMessage], server: [ChatMessage])
    
    /// 이전 메시지 로드
    func loadOlderMessages(room: ChatRoom, before messageID: String?) async throws -> [ChatMessage]
    
    /// 최신 메시지 로드
    func loadNewerMessages(room: ChatRoom, after messageID: String?) async throws -> [ChatMessage]
    
    /// 삭제 상태 동기화
    func syncDeletedStates(localMessages: [ChatMessage], room: ChatRoom) async throws -> [String]
    
    /// 메시지 삭제 처리
    func deleteMessage(message: ChatMessage, room: ChatRoom) async throws
    
    /// 실시간 메시지 수신 처리
    func handleIncomingMessage(_ message: ChatMessage, room: ChatRoom) async throws
    
    /// 삭제된 메시지 리스너 설정
    func setupDeletionListener(roomID: String, onDeleted: @escaping (String) -> Void) -> AnyCancellable
    
    /// 메시지 저장
    func saveMessage(_ message: ChatMessage, room: ChatRoom) async throws
}

