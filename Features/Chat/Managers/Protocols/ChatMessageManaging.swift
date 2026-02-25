//
//  ChatMessageManaging.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation
import Combine

/// 메시지 관리 관련 비즈니스 로직을 위한 프로토콜
protocol ChatMessageManaging {
    /// 참여자 초기 진입용 로컬 최근 메시지 로드
    func loadLocalRecentMessages(roomID: String, limit: Int) async throws -> [ChatMessage]

    /// 초기 진입용 서버 페이지 로드(reset=true)
    func fetchInitialServerMessages(room: ChatRoom, pageSize: Int) async throws -> [ChatMessage]

    /// 서버에서 불러온 초기 메시지를 로컬 저장 (prune 포함)
    func persistFetchedServerMessages(_ messages: [ChatMessage]) async throws

    /// 특정 anchor 메시지 주변 컨텍스트 로드 (검색 점프용)
    func loadMessagesAroundAnchor(
        room: ChatRoom,
        anchor: ChatMessage,
        beforeLimit: Int,
        afterLimit: Int
    ) async throws -> [ChatMessage]

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
