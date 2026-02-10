//
//  ChatRoomLifecycleUseCase.swift
//  OutPick
//
//  Created by Codex on 2/11/26.
//

import Foundation
import Combine

protocol ChatRoomLifecycleUseCaseProtocol {
    var roomChangePublisher: AnyPublisher<ChatRoom, Never> { get }

    @MainActor
    func startRoomUpdates(roomID: String)

    @MainActor
    func stopRoomUpdates()

    @MainActor
    func handleRoomSaved(roomID: String)

    @MainActor
    func joinRoom(roomID: String) async throws -> ChatRoom

    func updateLastReadSeq(roomID: String, userID: String, lastReadSeq: Int64) async throws

    @MainActor
    func setActiveAnnouncement(roomID: String, messageID: String?, payload: AnnouncementPayload?) async throws

    @MainActor
    func clearActiveAnnouncement(roomID: String) async throws
}

final class ChatRoomLifecycleUseCase: ChatRoomLifecycleUseCaseProtocol {
    private let firebaseManager: FirebaseManager
    private let socketManager: SocketIOManager

    init(
        firebaseManager: FirebaseManager = .shared,
        socketManager: SocketIOManager = .shared
    ) {
        self.firebaseManager = firebaseManager
        self.socketManager = socketManager
    }

    var roomChangePublisher: AnyPublisher<ChatRoom, Never> {
        firebaseManager.roomChangePublisher
    }

    @MainActor
    func startRoomUpdates(roomID: String) {
        guard !roomID.isEmpty else { return }
        firebaseManager.startListenRoomDoc(roomID: roomID)
    }

    @MainActor
    func stopRoomUpdates() {
        firebaseManager.stopListenAllRoomDocs()
    }

    @MainActor
    func handleRoomSaved(roomID: String) {
        guard !roomID.isEmpty else { return }
        firebaseManager.startListenRoomDoc(roomID: roomID)

        guard socketManager.isConnected else { return }
        socketManager.createRoom(roomID)
        socketManager.joinRoom(roomID)
    }

    @MainActor
    func joinRoom(roomID: String) async throws -> ChatRoom {
        guard !roomID.isEmpty else { throw FirebaseError.FailedToFetchRoom }

        if socketManager.isConnected {
            socketManager.joinRoom(roomID)
            socketManager.listenToNewParticipant()
        }

        let updatedRoom = try await firebaseManager.add_room_participant_returningRoom(roomID: roomID)
        firebaseManager.applyLocalRoomUpdate(updatedRoom)
        firebaseManager.startListenRoomDoc(roomID: roomID)

        return updatedRoom
    }

    func updateLastReadSeq(roomID: String, userID: String, lastReadSeq: Int64) async throws {
        try await firebaseManager.updateLastReadSeq(roomID: roomID, userID: userID, lastReadSeq: lastReadSeq)
    }

    @MainActor
    func setActiveAnnouncement(roomID: String, messageID: String?, payload: AnnouncementPayload?) async throws {
        try await firebaseManager.setActiveAnnouncement(roomID: roomID, messageID: messageID, payload: payload)
    }

    @MainActor
    func clearActiveAnnouncement(roomID: String) async throws {
        try await firebaseManager.clearActiveAnnouncement(roomID: roomID)
    }
}
