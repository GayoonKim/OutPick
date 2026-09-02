import Foundation

protocol ObserveChatRoomRoleUseCaseProtocol {
    @discardableResult
    func observe(
        roomID: String,
        userID: String,
        onUpdate: @escaping @Sendable (ChatRoomRoleSnapshot) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) -> ChatRoomRoleObservationCancelling

    func fetchMemberRole(roomID: String, userID: String) async throws -> ChatRoomMemberRole?
}

final class ObserveChatRoomRoleUseCase: ObserveChatRoomRoleUseCaseProtocol {
    private let repository: ChatRoomRoleRepositoryProtocol

    init(repository: ChatRoomRoleRepositoryProtocol) {
        self.repository = repository
    }

    @discardableResult
    func observe(
        roomID: String,
        userID: String,
        onUpdate: @escaping @Sendable (ChatRoomRoleSnapshot) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) -> ChatRoomRoleObservationCancelling {
        repository.observeCurrentRole(
            roomID: roomID,
            userID: userID,
            onUpdate: onUpdate,
            onError: onError
        )
    }

    func fetchMemberRole(roomID: String, userID: String) async throws -> ChatRoomMemberRole? {
        try await repository.fetchMemberRole(roomID: roomID, userID: userID)
    }
}

protocol ManageChatRoomRoleUseCaseProtocol {
    func assignModerator(roomID: String, targetUID: String) async throws -> ChatRoomRoleMutationReceipt
    func revokeModerator(roomID: String, targetUID: String) async throws -> ChatRoomRoleMutationReceipt
    func resignModerator(roomID: String) async throws -> ChatRoomRoleMutationReceipt
    func leaveRoom(roomID: String) async throws -> ChatRoomRoleMutationReceipt
    func transferOwnershipAndLeave(roomID: String, successorUID: String) async throws -> ChatRoomRoleMutationReceipt
}

final class ManageChatRoomRoleUseCase: ManageChatRoomRoleUseCaseProtocol {
    private let repository: ChatRoomRoleMutationRepositoryProtocol

    init(repository: ChatRoomRoleMutationRepositoryProtocol) {
        self.repository = repository
    }

    func assignModerator(roomID: String, targetUID: String) async throws -> ChatRoomRoleMutationReceipt {
        try await repository.assignModerator(roomID: roomID, targetUID: targetUID)
    }

    func revokeModerator(roomID: String, targetUID: String) async throws -> ChatRoomRoleMutationReceipt {
        try await repository.revokeModerator(roomID: roomID, targetUID: targetUID)
    }

    func resignModerator(roomID: String) async throws -> ChatRoomRoleMutationReceipt {
        try await repository.resignModerator(roomID: roomID)
    }

    func leaveRoom(roomID: String) async throws -> ChatRoomRoleMutationReceipt {
        try await repository.leaveChatRoom(roomID: roomID)
    }

    func transferOwnershipAndLeave(
        roomID: String,
        successorUID: String
    ) async throws -> ChatRoomRoleMutationReceipt {
        try await repository.transferOwnershipAndLeave(roomID: roomID, successorUID: successorUID)
    }
}
