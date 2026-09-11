//
//  ChatRoomExitUseCase.swift
//  OutPick
//
//  Created by Codex on 6/18/26.
//

import Foundation

protocol ChatRoomLocalExitCleaning {
    func cleanLocalRoomDataAfterExit(roomID: String) async throws
}

protocol ChatRoomExitUseCaseProtocol {
    func leaveOrClose(room: ChatRoom) async throws -> ChatRoomExitResult
    func transferOwnershipAndLeave(room: ChatRoom, successorUID: String) async throws -> ChatRoomExitResult
}

extension ChatRoomExitUseCaseProtocol {
    func transferOwnershipAndLeave(room: ChatRoom, successorUID: String) async throws -> ChatRoomExitResult {
        throw ChatRoomExitError.transferUnavailable
    }
}

protocol ChatRoomClosureAcknowledging {
    func acknowledge(roomID: String) async throws
}

final class ChatRoomClosureAcknowledgementUseCase: ChatRoomClosureAcknowledging {
    private let repository: ChatModerationLifecycleRepositoryProtocol
    private let localCleaner: ChatRoomLocalExitCleaning

    init(
        repository: ChatModerationLifecycleRepositoryProtocol,
        localCleaner: ChatRoomLocalExitCleaning
    ) {
        self.repository = repository
        self.localCleaner = localCleaner
    }

    func acknowledge(roomID: String) async throws {
        try await repository.acknowledgeClosureNotice(roomID: roomID)
        try await localCleaner.cleanLocalRoomDataAfterExit(roomID: roomID)
    }
}

enum ChatRoomExitError: LocalizedError, Equatable {
    case missingRoomID
    case transferUnavailable

    var errorDescription: String? {
        switch self {
        case .missingRoomID:
            return "방 정보를 확인할 수 없습니다."
        case .transferUnavailable:
            return "방장 권한을 이전할 수 없습니다."
        }
    }
}

final class ChatRoomExitUseCase: ChatRoomExitUseCaseProtocol {
    private let repository: ChatRoomExitRepositoryProtocol
    private let localCleaner: ChatRoomLocalExitCleaning
    private let roleMutationRepository: ChatRoomRoleMutationRepositoryProtocol?

    init(
        repository: ChatRoomExitRepositoryProtocol,
        localCleaner: ChatRoomLocalExitCleaning,
        roleMutationRepository: ChatRoomRoleMutationRepositoryProtocol? = nil
    ) {
        self.repository = repository
        self.localCleaner = localCleaner
        self.roleMutationRepository = roleMutationRepository
    }

    func leaveOrClose(room: ChatRoom) async throws -> ChatRoomExitResult {
        let roomID = room.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !roomID.isEmpty else {
            throw ChatRoomExitError.missingRoomID
        }

        let result = try await repository.leaveOrClose(room: room)
        do {
            try await localCleaner.cleanLocalRoomDataAfterExit(roomID: roomID)
        } catch {
            print("❌ local room exit cleanup failed:", error)
        }
        return result
    }

    func transferOwnershipAndLeave(
        room: ChatRoom,
        successorUID: String
    ) async throws -> ChatRoomExitResult {
        let roomID = room.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !roomID.isEmpty else { throw ChatRoomExitError.missingRoomID }
        guard let roleMutationRepository else { throw ChatRoomExitError.transferUnavailable }
        let receipt = try await roleMutationRepository.transferOwnershipAndLeave(
            roomID: roomID,
            successorUID: successorUID
        )
        do {
            try await localCleaner.cleanLocalRoomDataAfterExit(roomID: roomID)
        } catch {
            print("❌ local room ownership transfer cleanup failed:", error)
        }
        return ChatRoomExitResult(roomID: roomID, mode: receipt.exitMode ?? .left)
    }
}

final class DefaultChatRoomLocalExitCleaner: ChatRoomLocalExitCleaning {
    private let cacheSession: ChatMessageCacheSession?
    private let localDataStore: ChatRoomLocalDataPersisting
    private let joinedRoomsStore: JoinedRoomsSessionStoring
    private let joinedRoomsRuntime: JoinedRoomsSessionRuntimeHandling
    private let roomRepository: FirebaseChatRoomRepositoryProtocol
    private let currentUserProvider: CurrentUserProviding

    init(
        localDataStore: ChatRoomLocalDataPersisting,
        joinedRoomsStore: JoinedRoomsSessionStoring,
        joinedRoomsRuntime: JoinedRoomsSessionRuntimeHandling,
        roomRepository: FirebaseChatRoomRepositoryProtocol,
        currentUserProvider: CurrentUserProviding,
        cacheSession: ChatMessageCacheSession? = nil
    ) {
        self.localDataStore = localDataStore
        self.joinedRoomsStore = joinedRoomsStore
        self.joinedRoomsRuntime = joinedRoomsRuntime
        self.roomRepository = roomRepository
        self.currentUserProvider = currentUserProvider
        self.cacheSession = cacheSession
    }

    func cleanLocalRoomDataAfterExit(roomID: String) async throws {
        cacheSession?.invalidate(roomID: roomID)
        var localCleanupError: Error?
        do {
            try localDataStore.cleanRoomDataAfterExit(
                roomID: roomID,
                currentUserID: currentUserProvider.canonicalUserID
            )
        } catch {
            localCleanupError = error
        }

        await MainActor.run {
            joinedRoomsStore.remove(roomID)
            joinedRoomsRuntime.removeJoinedRoom(roomID)
        }

        if let localCleanupError {
            throw localCleanupError
        }
    }
}
