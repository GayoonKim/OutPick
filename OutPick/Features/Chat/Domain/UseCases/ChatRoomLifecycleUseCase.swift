//
//  ChatRoomLifecycleUseCase.swift
//  OutPick
//
//  Created by Codex on 2/11/26.
//

import Foundation

protocol ChatRoomLifecycleUseCaseProtocol {
    @MainActor
    func handleRoomSaved(roomID: String)

    @MainActor
    func joinRoom(roomID: String) async throws -> ChatRoom

    func updateLastReadSeq(roomID: String, userUID: String, lastReadSeq: Int64) async throws

    func fetchAuthoritativeLastReadSeq(roomID: String, userUID: String) async throws -> Int64?

    @MainActor
    func setActiveAnnouncement(roomID: String, messageID: String?, payload: AnnouncementPayload?) async throws

    @MainActor
    func clearActiveAnnouncement(roomID: String) async throws
}

extension ChatRoomLifecycleUseCaseProtocol {
    func fetchAuthoritativeLastReadSeq(roomID: String, userUID: String) async throws -> Int64? {
        nil
    }
}

protocol ChatRoomMembershipRealtimeManaging {
    func createRoom(_ roomID: String) async
}

final class ChatRoomLifecycleUseCase: ChatRoomLifecycleUseCaseProtocol {
    private let chatRoomRepository: FirebaseChatRoomRepositoryProtocol
    private let userProfileRepository: UserProfileRepositoryProtocol
    private let joinedRoomsStore: JoinedRoomsSessionStoring
    private let joinedRoomsRuntime: JoinedRoomsSessionRuntimeHandling
    private let announcementRepository: FirebaseAnnouncementRepositoryProtocol
    private let realtimeService: ChatRoomMembershipRealtimeManaging

    init(
        chatRoomRepository: FirebaseChatRoomRepositoryProtocol = FirebaseRepositoryProvider.shared.chatRoomRepository,
        userProfileRepository: UserProfileRepositoryProtocol = FirebaseRepositoryProvider.shared.userProfileRepository,
        joinedRoomsStore: JoinedRoomsSessionStoring,
        joinedRoomsRuntime: JoinedRoomsSessionRuntimeHandling,
        announcementRepository: FirebaseAnnouncementRepositoryProtocol = FirebaseRepositoryProvider.shared.announcementRepository,
        realtimeService: ChatRoomMembershipRealtimeManaging = RealtimeSocketService.shared
    ) {
        self.chatRoomRepository = chatRoomRepository
        self.userProfileRepository = userProfileRepository
        self.joinedRoomsStore = joinedRoomsStore
        self.joinedRoomsRuntime = joinedRoomsRuntime
        self.announcementRepository = announcementRepository
        self.realtimeService = realtimeService
    }

    @MainActor
    func handleRoomSaved(roomID: String) {
        guard !roomID.isEmpty else { return }
        activateJoinedRoomRealtime(roomID: roomID)
        Task {
            await realtimeService.createRoom(roomID)
        }
    }

    @MainActor
    func joinRoom(roomID: String) async throws -> ChatRoom {
        guard !roomID.isEmpty else { throw FirebaseError.FailedToFetchRoom }
        let updatedRoom = try await chatRoomRepository.addRoomParticipantReturningRoom(roomID: roomID)
        chatRoomRepository.applyLocalRoomUpdate(updatedRoom)
        activateJoinedRoomRealtime(roomID: roomID)

        return updatedRoom
    }

    func updateLastReadSeq(roomID: String, userUID: String, lastReadSeq: Int64) async throws {
        try await userProfileRepository.updateLastReadSeq(roomID: roomID, userUID: userUID, lastReadSeq: lastReadSeq)
    }

    func fetchAuthoritativeLastReadSeq(roomID: String, userUID: String) async throws -> Int64? {
        try await userProfileRepository.fetchAuthoritativeLastReadSeq(
            for: roomID,
            userUID: userUID
        )
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
        joinedRoomsStore.add(roomID)
        joinedRoomsRuntime.addJoinedRoom(roomID)
    }
}

extension RealtimeSocketService: ChatRoomMembershipRealtimeManaging {}
