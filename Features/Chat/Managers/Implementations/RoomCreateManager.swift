//
//  RoomCreateManager.swift
//  OutPick
//
//  Created by Codex on 2/25/26.
//

import Foundation
import UIKit
import FirebaseFirestore

struct RoomCreateManager: RoomCreateManaging {
    let chatRoomRepository: FirebaseChatRoomRepositoryProtocol
    let imageStorageRepository: FirebaseImageStorageRepositoryProtocol
    let roomImageManager: RoomImageManaging

    init(
        chatRoomRepository: FirebaseChatRoomRepositoryProtocol,
        imageStorageRepository: FirebaseImageStorageRepositoryProtocol,
        roomImageManager: RoomImageManaging = RoomImageService.shared
    ) {
        self.chatRoomRepository = chatRoomRepository
        self.imageStorageRepository = imageStorageRepository
        self.roomImageManager = roomImageManager
    }

    var currentUserEmail: String {
        LoginManager.shared.getUserEmail
    }

    func generateRoomID() -> String {
        Firestore.firestore().collection("Rooms").document().documentID
    }

    func checkRoomNameDuplicate(_ roomName: String) async throws -> Bool {
        try await chatRoomRepository.checkRoomNameDuplicate(roomName: roomName)
    }

    func saveRoom(_ room: ChatRoom) async throws {
        try await chatRoomRepository.saveRoomInfoToFirestore(room: room)
    }

    func uploadAndCacheRoomImage(pair: DefaultMediaProcessingService.ImagePair, roomID: String) async throws {
        let (thumbPath, _) = try await imageStorageRepository.uploadAndSave(
            sha: pair.fileBaseName,
            uid: roomID,
            type: .roomImage,
            thumbData: pair.thumbData,
            originalFileURL: pair.originalFileURL,
            versionHint: nil,
            contentType: "image/jpeg"
        )

        try await roomImageManager.storeImageDataToCache(pair.thumbData, for: thumbPath)
    }
}
