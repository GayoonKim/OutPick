//
//  JoinedRoomsUseCase.swift
//  OutPick
//
//  Created by Codex on 2/10/26.
//

import Foundation
import Combine

protocol JoinedRoomsUseCaseProtocol {
    var roomChangePublisher: AnyPublisher<ChatRoom, Never> { get }

    func fetchJoinedRooms() async throws -> [ChatRoom]
    @MainActor
    func startRoomUpdates(roomIDs: [String])
    @MainActor
    func stopRoomUpdates()
    func fetchUnreadCount(roomID: String, lastMessageSeqHint: Int64?) async -> Int64
    func leave(room: ChatRoom)
}

final class JoinedRoomsUseCase: JoinedRoomsUseCaseProtocol {
    let roomChangePublisher: AnyPublisher<ChatRoom, Never>

    private let roomRepository: ChatRoomRepositoryProtocol
    private let userProfileRepository: UserProfileRepositoryProtocol

    init(
        roomRepository: ChatRoomRepositoryProtocol,
        userProfileRepository: UserProfileRepositoryProtocol
    ) {
        self.roomRepository = roomRepository
        self.userProfileRepository = userProfileRepository
        self.roomChangePublisher = roomRepository.roomChangePublisher
    }

    func fetchJoinedRooms() async throws -> [ChatRoom] {
        guard let profile = LoginManager.shared.currentUserProfile else { return [] }
        return try await roomRepository.fetchRoomsWithIDs(byIDs: profile.joinedRooms)
    }

    @MainActor
    func startRoomUpdates(roomIDs: [String]) {
        roomRepository.startListenRoomDocs(roomIDs: roomIDs)
    }

    @MainActor
    func stopRoomUpdates() {
        roomRepository.stopListenAllRoomDocs()
    }

    func fetchUnreadCount(roomID: String, lastMessageSeqHint: Int64?) async -> Int64 {
        do {
            let lastRead = try await userProfileRepository.fetchLastReadSeq(for: roomID)
            let latest: Int64
            if let lastMessageSeqHint {
                latest = lastMessageSeqHint
            } else {
                latest = try await roomRepository.fetchLatestSeq(for: roomID)
            }
            return max(Int64(0), latest - lastRead)
        } catch {
            print("⚠️ unread 계산 실패(roomID=\(roomID)): \(error)")
            return 0
        }
    }

    func leave(room: ChatRoom) {
        roomRepository.remove_participant(room: room)
    }
}
