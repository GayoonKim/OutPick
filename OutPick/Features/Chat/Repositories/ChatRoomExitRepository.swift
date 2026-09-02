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
    func leaveOrClose(room: ChatRoom) async throws -> ChatRoomExitResult
}

protocol ChatRoomExitSocketRequesting: AnyObject {
    func leaveOrCloseRoom(roomID: String, ackTimeout: Double) async throws -> ChatRoomExitMode
}

final class DefaultChatRoomExitRepository: ChatRoomExitRepositoryProtocol {
    private let socket: ChatRoomExitSocketRequesting
    private let moderationLifecycleRepository: ChatModerationLifecycleRepositoryProtocol
    private let roleMutationRepository: ChatRoomRoleMutationRepositoryProtocol
    private let currentUserID: () -> String

    init(
        socket: ChatRoomExitSocketRequesting = RealtimeSocketService.shared,
        moderationLifecycleRepository: ChatModerationLifecycleRepositoryProtocol =
            CloudFunctionsChatModerationLifecycleRepository(),
        roleMutationRepository: ChatRoomRoleMutationRepositoryProtocol =
            CloudFunctionsChatModerationLifecycleRepository(),
        currentUserID: @escaping () -> String = { LoginManager.shared.canonicalUserID }
    ) {
        self.socket = socket
        self.moderationLifecycleRepository = moderationLifecycleRepository
        self.roleMutationRepository = roleMutationRepository
        self.currentUserID = currentUserID
    }

    func leaveOrClose(room: ChatRoom) async throws -> ChatRoomExitResult {
        let roomID = room.id
        if room.ownerUID == currentUserID() {
            return try await moderationLifecycleRepository.closeOwnedRoom(
                roomID: roomID,
                expectedLifecycleVersion: room.lifecycleVersion
            )
        }
        _ = socket
        let receipt = try await roleMutationRepository.leaveChatRoom(roomID: roomID)
        return ChatRoomExitResult(roomID: roomID, mode: receipt.exitMode ?? .left)
    }
}

extension RealtimeSocketService: ChatRoomExitSocketRequesting {}
