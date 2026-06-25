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
}

enum ChatRoomExitError: LocalizedError, Equatable {
    case missingRoomID

    var errorDescription: String? {
        switch self {
        case .missingRoomID:
            return "방 정보를 확인할 수 없습니다."
        }
    }
}

final class ChatRoomExitUseCase: ChatRoomExitUseCaseProtocol {
    private let repository: ChatRoomExitRepositoryProtocol
    private let localCleaner: ChatRoomLocalExitCleaning

    init(
        repository: ChatRoomExitRepositoryProtocol,
        localCleaner: ChatRoomLocalExitCleaning
    ) {
        self.repository = repository
        self.localCleaner = localCleaner
    }

    func leaveOrClose(room: ChatRoom) async throws -> ChatRoomExitResult {
        guard let roomID = room.ID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !roomID.isEmpty else {
            throw ChatRoomExitError.missingRoomID
        }

        let result = try await repository.leaveOrClose(roomID: roomID)
        do {
            try await localCleaner.cleanLocalRoomDataAfterExit(roomID: roomID)
        } catch {
            print("❌ local room exit cleanup failed:", error)
        }
        return result
    }
}

final class DefaultChatRoomLocalExitCleaner: ChatRoomLocalExitCleaning {
    private let grdbManager: GRDBManager
    private let loginManager: LoginManager
    private let joinedRoomsStore: JoinedRoomsSessionStoring
    private let joinedRoomsRuntime: JoinedRoomsSessionRuntimeHandling
    private let roomRepository: FirebaseChatRoomRepositoryProtocol

    init(
        grdbManager: GRDBManager = .shared,
        loginManager: LoginManager = .shared,
        joinedRoomsStore: JoinedRoomsSessionStoring,
        joinedRoomsRuntime: JoinedRoomsSessionRuntimeHandling,
        roomRepository: FirebaseChatRoomRepositoryProtocol
    ) {
        self.grdbManager = grdbManager
        self.loginManager = loginManager
        self.joinedRoomsStore = joinedRoomsStore
        self.joinedRoomsRuntime = joinedRoomsRuntime
        self.roomRepository = roomRepository
    }

    func cleanLocalRoomDataAfterExit(roomID: String) async throws {
        var localCleanupError: Error?
        do {
            try grdbManager.deleteLocalRoomDataAndPruneUsers(roomID: roomID)
        } catch {
            localCleanupError = error
        }

        await MainActor.run {
            if var profile = loginManager.currentUserProfile {
                profile.joinedRooms.removeAll { $0 == roomID }
                loginManager.setCurrentUserProfile(profile)
            }
            joinedRoomsStore.remove(roomID)
            joinedRoomsRuntime.removeJoinedRoom(roomID)
            roomRepository.removeLocalJoinedRoom(roomID: roomID)
        }

        if let localCleanupError {
            throw localCleanupError
        }
    }
}
