//
//  JoinedRoomsUseCase.swift
//  OutPick
//
//  Created by Codex on 2/10/26.
//

import Foundation
import Combine
import FirebaseFirestore

protocol JoinedRoomsUseCaseProtocol {
    var joinedRoomsPublisher: AnyPublisher<[ChatRoom], Never> { get }

    func fetchJoinedRoomsHead(limit: Int) async throws -> (rooms: [ChatRoom], cursor: DocumentSnapshot?)
    func loadMoreJoinedRooms(after cursor: DocumentSnapshot?, limit: Int) async throws -> (rooms: [ChatRoom], cursor: DocumentSnapshot?)
    func syncJoinedRoomsTail(since: Date, limit: Int) async throws -> [ChatRoom]
    @MainActor
    func startRoomUpdates(limit: Int)
    @MainActor
    func stopRoomUpdates()
    func fetchUnreadCount(roomID: String, lastMessageSeqHint: Int64?, lastMessageSenderID: String?) async -> Int64
    func leave(room: ChatRoom)
}

final class JoinedRoomsUseCase: JoinedRoomsUseCaseProtocol {
    let joinedRoomsPublisher: AnyPublisher<[ChatRoom], Never>

    private let roomRepository: FirebaseChatRoomRepositoryProtocol
    private let userProfileRepository: UserProfileRepositoryProtocol
    private let joinedRoomsStore: JoinedRoomsStore

    init(
        roomRepository: FirebaseChatRoomRepositoryProtocol,
        userProfileRepository: UserProfileRepositoryProtocol,
        joinedRoomsStore: JoinedRoomsStore
    ) {
        self.roomRepository = roomRepository
        self.userProfileRepository = userProfileRepository
        self.joinedRoomsStore = joinedRoomsStore
        self.joinedRoomsPublisher = roomRepository.joinedRoomsSummaryPublisher
    }

    func fetchJoinedRoomsHead(limit: Int = 50) async throws -> (rooms: [ChatRoom], cursor: DocumentSnapshot?) {
        let page = try await roomRepository.fetchJoinedRoomsPage(
            userEmail: LoginManager.shared.getUserEmail,
            after: nil,
            limit: limit
        )
        return (rooms: page.rooms, cursor: page.lastSnapshot)
    }

    func loadMoreJoinedRooms(after cursor: DocumentSnapshot?, limit: Int = 50) async throws -> (rooms: [ChatRoom], cursor: DocumentSnapshot?) {
        let page = try await roomRepository.fetchJoinedRoomsPage(
            userEmail: LoginManager.shared.getUserEmail,
            after: cursor,
            limit: limit
        )
        return (rooms: page.rooms, cursor: page.lastSnapshot)
    }

    func syncJoinedRoomsTail(since: Date, limit: Int = 200) async throws -> [ChatRoom] {
        try await roomRepository.fetchJoinedRoomsUpdatedSince(
            userEmail: LoginManager.shared.getUserEmail,
            since: since,
            limit: limit
        )
    }

    @MainActor
    func startRoomUpdates(limit: Int = 50) {
        roomRepository.startListenJoinedRoomsSummary(
            userEmail: LoginManager.shared.getUserEmail,
            limit: limit
        )
    }

    @MainActor
    func stopRoomUpdates() {
        roomRepository.stopListenJoinedRoomsSummary()
    }

    func fetchUnreadCount(roomID: String, lastMessageSeqHint: Int64?, lastMessageSenderID: String?) async -> Int64 {
        do {
            let lastRead = try await userProfileRepository.fetchLastReadSeq(for: roomID)
            let latest: Int64 = {
                if let hint = lastMessageSeqHint, hint > 0, hint > lastRead {
                    return hint
                }
                return 0
            }()
            let resolvedLatest: Int64
            if latest > 0 {
                resolvedLatest = latest
            } else {
                resolvedLatest = try await roomRepository.fetchLatestSeq(for: roomID)
            }
            var unread = max(Int64(0), resolvedLatest - lastRead)
            let currentUserID = LoginManager.shared.getUserEmail
            if unread > 0,
               let lastMessageSenderID,
               !lastMessageSenderID.isEmpty,
               lastMessageSenderID == currentUserID {
                unread = max(Int64(0), unread - 1)
            }
            return unread
        } catch {
            print("⚠️ unread 계산 실패(roomID=\(roomID)): \(error)")
            return 0
        }
    }

    func leave(room: ChatRoom) {
        if let roomID = room.ID, !roomID.isEmpty {
            Task { @MainActor [joinedRoomsStore] in
                joinedRoomsStore.remove(roomID)
            }
        }
        roomRepository.removeParticipant(room: room)
    }
}
