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
    private let chatRoomRepository: ChatRoomRepositoryProtocol
    private let userProfileRepository: UserProfileRepositoryProtocol
    private let announcementRepository: AnnouncementRepositoryProtocol
    private let socketManager: SocketIOManager

    init(
        chatRoomRepository: ChatRoomRepositoryProtocol = FirebaseRepositoryProvider.shared.chatRoomRepository,
        userProfileRepository: UserProfileRepositoryProtocol = FirebaseRepositoryProvider.shared.userProfileRepository,
        announcementRepository: AnnouncementRepositoryProtocol = FirebaseRepositoryProvider.shared.announcementRepository,
        socketManager: SocketIOManager = .shared
    ) {
        self.chatRoomRepository = chatRoomRepository
        self.userProfileRepository = userProfileRepository
        self.announcementRepository = announcementRepository
        self.socketManager = socketManager
    }

    var roomChangePublisher: AnyPublisher<ChatRoom, Never> {
        chatRoomRepository.roomChangePublisher
    }

    @MainActor
    func startRoomUpdates(roomID: String) {
        guard !roomID.isEmpty else { return }
        chatRoomRepository.startListenRoomDoc(roomID: roomID)
    }

    @MainActor
    func stopRoomUpdates() {
        chatRoomRepository.stopListenAllRoomDocs()
    }

    @MainActor
    func handleRoomSaved(roomID: String) {
        guard !roomID.isEmpty else { return }
        chatRoomRepository.startListenRoomDoc(roomID: roomID)

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

        let updatedRoom = try await chatRoomRepository.add_room_participant_returningRoom(roomID: roomID)
        chatRoomRepository.applyLocalRoomUpdate(updatedRoom)
        chatRoomRepository.startListenRoomDoc(roomID: roomID)

        return updatedRoom
    }

    func updateLastReadSeq(roomID: String, userID: String, lastReadSeq: Int64) async throws {
        try await userProfileRepository.updateLastReadSeq(roomID: roomID, userID: userID, lastReadSeq: lastReadSeq)
    }

    @MainActor
    func setActiveAnnouncement(roomID: String, messageID: String?, payload: AnnouncementPayload?) async throws {
        try await announcementRepository.setActiveAnnouncement(roomID: roomID, messageID: messageID, payload: payload)
    }

    @MainActor
    func clearActiveAnnouncement(roomID: String) async throws {
        try await announcementRepository.clearActiveAnnouncement(roomID: roomID)
    }
}
