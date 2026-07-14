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
}

protocol CreateRoomUseCaseProtocol {
    func execute(
        roomName: String,
        roomDescription: String,
        imagePair: ProcessedImage?,
        onEvent: @escaping @MainActor (CreateRoomUseCaseEvent) -> Void
    ) async throws
}

@MainActor
final class CreateRoomUseCase: CreateRoomUseCaseProtocol {
    private let chatRoomRepository: CreateRoomRepositoryProtocol
    private let imageStorageRepository: FirebaseImageStorageRepositoryProtocol
    private let roomImageManager: RoomImageManaging
    private let currentUserUIDProvider: @Sendable () -> String

    init(
        chatRoomRepository: CreateRoomRepositoryProtocol,
        imageStorageRepository: FirebaseImageStorageRepositoryProtocol,
        roomImageManager: RoomImageManaging,
        currentUserUIDProvider: @escaping @Sendable () -> String = { LoginManager.shared.canonicalUserID }
    ) {
        self.chatRoomRepository = chatRoomRepository
        self.imageStorageRepository = imageStorageRepository
        self.roomImageManager = roomImageManager
        self.currentUserUIDProvider = currentUserUIDProvider
    }

    func execute(
        roomName: String,
        roomDescription: String,
        imagePair: ProcessedImage?,
        onEvent: @escaping @MainActor (CreateRoomUseCaseEvent) -> Void
    ) async throws {
        let isDuplicate = try await chatRoomRepository.checkRoomNameDuplicate(roomName: roomName)
        if isDuplicate {
            throw RoomCreationError.duplicateName
        }

        let currentUserUID = currentUserUIDProvider()
        let input = CreateChatRoomInput(
            roomName: roomName,
            roomDescription: roomDescription,
            creatorUID: currentUserUID,
            createdAt: Date()
        )

        // Core write must succeed before the UI treats the room as created.
        let room: ChatRoom
        do {
            room = try await chatRoomRepository.createRoom(input: input)
        } catch {
            throw (error as? RoomCreationError) ?? .saveFailed
        }

        onEvent(.presentCreatedRoom(room))
        onEvent(.roomSaveCompleted(room))

        if let imagePair, !room.id.isEmpty {
            Task(priority: .background) { [weak self] in
                guard let self else { return }
                do {
                    try await self.uploadRoomImageAndPatchRoom(
                        room: room,
                        roomID: room.id,
                        imagePair: imagePair
                    )
                } catch {
                    // 대표 이미지 업로드 실패는 비치명 처리
                    print("방 대표 사진 업로드 실패: \(error)")
                }
            }
        }
    }

    private func uploadRoomImageAndPatchRoom(
        room: ChatRoom,
        roomID: String,
        imagePair: ProcessedImage
    ) async throws {
        defer { try? FileManager.default.removeItem(at: imagePair.originalFileURL) }

        let (thumbPath, originalPath) = try await imageStorageRepository.uploadImage(
            sha: imagePair.fileBaseName,
            uid: roomID,
            type: .roomImage,
            thumbData: imagePair.thumbData,
            originalFileURL: imagePair.originalFileURL,
            contentType: "image/jpeg"
        )

        do {
            try await chatRoomRepository.updateRoomMetadataWithImagePaths(
                roomID: roomID,
                roomName: room.roomName,
                roomDescription: room.roomDescription,
                thumbPath: thumbPath,
                originalPath: originalPath
            )
        } catch {
            imageStorageRepository.deleteImageFromStorage(path: thumbPath)
            imageStorageRepository.deleteImageFromStorage(path: originalPath)
            await roomImageManager.removeCachedImage(for: thumbPath)
            throw error
        }

        try? await roomImageManager.storeImageDataToCache(imagePair.thumbData, for: thumbPath)

        var updatedRoom = room
        updatedRoom.thumbPath = thumbPath
        updatedRoom.originalPath = originalPath
        chatRoomRepository.applyLocalRoomUpdate(updatedRoom)
    }
}
