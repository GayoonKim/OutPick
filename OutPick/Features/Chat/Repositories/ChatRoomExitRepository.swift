//
//  ChatRoomExitRepository.swift
//  OutPick
//
//  Created by Codex on 6/18/26.
//

import Foundation

enum ChatRoomExitMode: Equatable {
    case left
    case closed
    case unknown(String?)

    init(serverValue: String?) {
        switch serverValue {
        case "left":
            self = .left
        case "closed":
            self = .closed
        case let value:
            self = .unknown(value)
        }
    }
}

struct ChatRoomExitResult: Equatable {
    let roomID: String
    let mode: ChatRoomExitMode
}

protocol ChatRoomExitRepositoryProtocol {
    func leaveOrClose(roomID: String) async throws -> ChatRoomExitResult
}

protocol ChatRoomExitSocketRequesting: AnyObject {
    func leaveOrCloseRoom(roomID: String, ackTimeout: Double) async throws -> ChatRoomExitMode
}

final class SocketChatRoomExitRepository: ChatRoomExitRepositoryProtocol {
    private let socket: ChatRoomExitSocketRequesting

    init(socket: ChatRoomExitSocketRequesting = RealtimeSocketService.shared) {
        self.socket = socket
    }

    func leaveOrClose(roomID: String) async throws -> ChatRoomExitResult {
        let mode = try await socket.leaveOrCloseRoom(roomID: roomID, ackTimeout: 10.0)
        return ChatRoomExitResult(roomID: roomID, mode: mode)
    }
}

extension RealtimeSocketService: ChatRoomExitSocketRequesting {}
