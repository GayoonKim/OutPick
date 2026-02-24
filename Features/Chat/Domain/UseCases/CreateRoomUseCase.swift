//
//  CreateRoomUseCase.swift
//  OutPick
//
//  Created by Codex on 2/25/26.
//

import Foundation

enum CreateRoomUseCaseEvent {
    case presentCreatedRoom(ChatRoom)
    case roomSaveCompleted(ChatRoom)
    case roomSaveFailed(RoomCreationError)
}

protocol CreateRoomUseCaseProtocol {
    func execute(
        roomName: String,
        roomDescription: String,
        imagePair: DefaultMediaProcessingService.ImagePair?,
        onEvent: @escaping @MainActor (CreateRoomUseCaseEvent) -> Void
    ) async throws
}

@MainActor
final class CreateRoomUseCase: CreateRoomUseCaseProtocol {
    private let manager: RoomCreateManaging

    init(manager: RoomCreateManaging) {
        self.manager = manager
    }

    func execute(
        roomName: String,
        roomDescription: String,
        imagePair: DefaultMediaProcessingService.ImagePair?,
        onEvent: @escaping @MainActor (CreateRoomUseCaseEvent) -> Void
    ) async throws {
        let isDuplicate = try await manager.checkRoomNameDuplicate(roomName)
        if isDuplicate {
            throw RoomCreationError.duplicateName
        }

        let room = ChatRoom(
            ID: manager.generateRoomID(),
            roomName: roomName,
            roomDescription: roomDescription,
            participants: [manager.currentUserEmail],
            creatorID: manager.currentUserEmail,
            createdAt: Date()
        )

        // Core write must succeed before the UI treats the room as created.
        do {
            try await manager.saveRoom(room)
        } catch {
            throw (error as? RoomCreationError) ?? .saveFailed
        }

        onEvent(.presentCreatedRoom(room))
        onEvent(.roomSaveCompleted(room))

        if let imagePair, let roomID = room.ID, !roomID.isEmpty {
            Task(priority: .background) { [weak self] in
                guard let self else { return }
                do {
                    try await self.manager.uploadAndCacheRoomImage(pair: imagePair, roomID: roomID)
                } catch {
                    // 대표 이미지 업로드 실패는 비치명 처리
                    print("방 대표 사진 업로드 실패: \(error)")
                }
            }
        }
    }
}
