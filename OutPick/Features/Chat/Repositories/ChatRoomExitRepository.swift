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
    func requestLeaveOrCloseRoomResult(
        roomID: String,
        ackTimeout: Double,
        completion: ((Result<ChatRoomExitMode, Error>) -> Void)?
    )
}

final class SocketChatRoomExitRepository: ChatRoomExitRepositoryProtocol {
    private let socket: ChatRoomExitSocketRequesting

    init(socket: ChatRoomExitSocketRequesting = SocketIOManager.shared) {
        self.socket = socket
    }

    func leaveOrClose(roomID: String) async throws -> ChatRoomExitResult {
        try await withCheckedThrowingContinuation { continuation in
            socket.requestLeaveOrCloseRoomResult(roomID: roomID, ackTimeout: 10.0) { result in
                switch result {
                case .success(let mode):
                    continuation.resume(returning: ChatRoomExitResult(roomID: roomID, mode: mode))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

extension SocketIOManager: ChatRoomExitSocketRequesting {}
