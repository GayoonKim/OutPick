//
//  ChatRoomRealtimeRepository.swift
//  OutPick
//
//  Created by Codex on 6/17/26.
//

import Foundation

struct ChatRoomRealtimeSession: Sendable {
    let roomID: String
    let messages: AsyncStream<ChatMessage>
    let close: @Sendable () async -> Void
}

protocol ChatRoomRealtimeRepositoryProtocol {
    func openMessageStream(roomID: String) async throws -> ChatRoomRealtimeSession
}

protocol ChatRoomRealtimeSocketOpening {
    func openRoomSession(for roomID: String) async throws -> ChatRoomSocketSession
}

final class SocketChatRoomRealtimeRepository: ChatRoomRealtimeRepositoryProtocol {
    private let socketManager: ChatRoomRealtimeSocketOpening

    init(socketManager: ChatRoomRealtimeSocketOpening = SocketIOManager.shared) {
        self.socketManager = socketManager
    }

    func openMessageStream(roomID: String) async throws -> ChatRoomRealtimeSession {
        let session = try await socketManager.openRoomSession(for: roomID)
        return ChatRoomRealtimeSession(
            roomID: session.roomID,
            messages: session.messages,
            close: session.close
        )
    }
}

extension SocketIOManager: ChatRoomRealtimeSocketOpening {}
