//
//  RoomEditUseCase.swift
//  OutPick
//
//  Created by Codex on 3/27/26.
//

import Foundation
import UIKit

protocol RoomEditUseCaseProtocol {
    func loadHeaderImage(for room: ChatRoom) async throws -> UIImage
    func execute(
        room: ChatRoom,
        imagePair: DefaultMediaProcessingService.ImagePair?,
        isImageRemoved: Bool,
        roomName: String,
        roomDescription: String
    ) async throws -> ChatRoom
}

final class RoomEditUseCase: RoomEditUseCaseProtocol {
    private struct UploadedRoomImage {
        let thumbPath: String
        let originalPath: String
        let previewData: Data
    }

    private let chatRoomRepository: FirebaseChatRoomRepositoryProtocol
    private let imageStorageRepository: FirebaseImageStorageRepositoryProtocol
    private let roomImageManager: RoomImageManaging
    private let maxHeaderImageBytes = 3 * 1024 * 1024

    init(
        chatRoomRepository: FirebaseChatRoomRepositoryProtocol,
        imageStorageRepository: FirebaseImageStorageRepositoryProtocol,
        roomImageManager: RoomImageManaging
    ) {
        self.chatRoomRepository = chatRoomRepository
        self.imageStorageRepository = imageStorageRepository
        self.roomImageManager = roomImageManager
    }

    func loadHeaderImage(for room: ChatRoom) async throws -> UIImage {
        let key = room.thumbPath ?? room.originalPath
        guard let key, !key.isEmpty else {
            throw MediaError.failedToConvertImage
        }
        return try await roomImageManager.loadImage(for: key, maxBytes: maxHeaderImageBytes)
    }

    func execute(
        room: ChatRoom,
        imagePair: DefaultMediaProcessingService.ImagePair?,
        isImageRemoved: Bool,
        roomName: String,
        roomDescription: String
    ) async throws -> ChatRoom {
        guard let roomID = room.ID, !roomID.isEmpty else {
            throw FirebaseError.FailedToFetchRoom
        }

        let previousImagePaths = existingImagePaths(in: room)
        var updatedRoom = room
        updatedRoom.roomName = roomName
        updatedRoom.roomDescription = roomDescription

        if isImageRemoved {
            try await chatRoomRepository.removeRoomImagePathsAndUpdateMetadata(
                roomID: roomID,
                roomName: roomName,
                roomDescription: roomDescription
            )
            updatedRoom.thumbPath = nil
            updatedRoom.originalPath = nil

            await cleanupCache(for: previousImagePaths)
            cleanupStorage(for: previousImagePaths)
        } else if let imagePair {
            let uploadedImage = try await uploadRoomImage(pair: imagePair, roomID: roomID)

            do {
                try await chatRoomRepository.updateRoomMetadataWithImagePaths(
                    roomID: roomID,
                    roomName: roomName,
                    roomDescription: roomDescription,
                    thumbPath: uploadedImage.thumbPath,
                    originalPath: uploadedImage.originalPath
                )
            } catch {
                cleanupStorage(for: [uploadedImage.thumbPath, uploadedImage.originalPath])
                await cleanupCache(for: [uploadedImage.thumbPath])
                throw error
            }

            updatedRoom.thumbPath = uploadedImage.thumbPath
            updatedRoom.originalPath = uploadedImage.originalPath

            try? await roomImageManager.storeImageDataToCache(uploadedImage.previewData, for: uploadedImage.thumbPath)
            await cleanupCache(for: previousImagePaths.filter { $0 != uploadedImage.thumbPath && $0 != uploadedImage.originalPath })
            cleanupStorage(for: previousImagePaths.filter { $0 != uploadedImage.thumbPath && $0 != uploadedImage.originalPath })
            cleanupTemporaryFileIfNeeded(for: imagePair)
        } else {
            try await chatRoomRepository.updateRoomMetadata(
                roomID: roomID,
                roomName: roomName,
                roomDescription: roomDescription
            )
        }

        chatRoomRepository.applyLocalRoomUpdate(updatedRoom)
        return updatedRoom
    }

    private func uploadRoomImage(
        pair: DefaultMediaProcessingService.ImagePair,
        roomID: String
    ) async throws -> UploadedRoomImage {
        let (thumbPath, originalPath) = try await imageStorageRepository.uploadImage(
            sha: pair.fileBaseName,
            uid: roomID,
            type: .roomImage,
            thumbData: pair.thumbData,
            originalFileURL: pair.originalFileURL,
            contentType: "image/jpeg"
        )

        return UploadedRoomImage(
            thumbPath: thumbPath,
            originalPath: originalPath,
            previewData: pair.thumbData
        )
    }

    private func existingImagePaths(in room: ChatRoom) -> [String] {
        [room.thumbPath, room.originalPath]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
    }

    private func cleanupStorage(for paths: [String]) {
        let uniquePaths = Array(Set(paths.filter { !$0.isEmpty }))
        for path in uniquePaths {
            imageStorageRepository.deleteImageFromStorage(path: path)
        }
    }

    private func cleanupCache(for paths: [String]) async {
        let uniquePaths = Array(Set(paths.filter { !$0.isEmpty }))
        for path in uniquePaths {
            await roomImageManager.removeCachedImage(for: path)
        }
    }

    private func cleanupTemporaryFileIfNeeded(for imagePair: DefaultMediaProcessingService.ImagePair?) {
        guard let imagePair else { return }
        try? FileManager.default.removeItem(at: imagePair.originalFileURL)
    }
}
