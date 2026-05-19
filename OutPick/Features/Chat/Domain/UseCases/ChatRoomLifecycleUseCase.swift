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

    func updateLastReadSeq(roomID: String, userUID: String, lastReadSeq: Int64) async throws

    @MainActor
    func setActiveAnnouncement(roomID: String, messageID: String?, payload: AnnouncementPayload?) async throws

    @MainActor
    func clearActiveAnnouncement(roomID: String) async throws
}

final class ChatRoomLifecycleUseCase: ChatRoomLifecycleUseCaseProtocol {
    private let chatRoomRepository: FirebaseChatRoomRepositoryProtocol
    private let userProfileRepository: UserProfileRepositoryProtocol
    private let joinedRoomsStore: JoinedRoomsStore
    private let announcementRepository: FirebaseAnnouncementRepositoryProtocol
    private let socketManager: SocketIOManager

    init(
        chatRoomRepository: FirebaseChatRoomRepositoryProtocol = FirebaseRepositoryProvider.shared.chatRoomRepository,
        userProfileRepository: UserProfileRepositoryProtocol = FirebaseRepositoryProvider.shared.userProfileRepository,
        joinedRoomsStore: JoinedRoomsStore,
        announcementRepository: FirebaseAnnouncementRepositoryProtocol = FirebaseRepositoryProvider.shared.announcementRepository,
        socketManager: SocketIOManager = .shared
    ) {
        self.chatRoomRepository = chatRoomRepository
        self.userProfileRepository = userProfileRepository
        self.joinedRoomsStore = joinedRoomsStore
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
        chatRoomRepository.stopListenRoomDoc()
    }

    @MainActor
    func handleRoomSaved(roomID: String) {
        guard !roomID.isEmpty else { return }
        activateJoinedRoomRealtime(roomID: roomID)
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

        let updatedRoom = try await chatRoomRepository.addRoomParticipantReturningRoom(roomID: roomID)
        chatRoomRepository.applyLocalRoomUpdate(updatedRoom)
        activateJoinedRoomRealtime(roomID: roomID)

        return updatedRoom
    }

    func updateLastReadSeq(roomID: String, userUID: String, lastReadSeq: Int64) async throws {
        try await userProfileRepository.updateLastReadSeq(roomID: roomID, userUID: userUID, lastReadSeq: lastReadSeq)
    }

    @MainActor
    func setActiveAnnouncement(roomID: String, messageID: String?, payload: AnnouncementPayload?) async throws {
        try await announcementRepository.setActiveAnnouncement(roomID: roomID, messageID: messageID, payload: payload)
    }

    @MainActor
    func clearActiveAnnouncement(roomID: String) async throws {
        try await announcementRepository.clearActiveAnnouncement(roomID: roomID)
    }

    @MainActor
    private func activateJoinedRoomRealtime(roomID: String) {
        guard !roomID.isEmpty else { return }
        chatRoomRepository.startListenRoomDoc(roomID: roomID)
        joinedRoomsStore.add(roomID)
        // Directly register the banner subscription on join success to avoid
        // timing gaps while the JoinedRoomsStore -> ChatContainer pipeline catches up.
        BannerManager.shared.addRoom(roomID)
    }
}
