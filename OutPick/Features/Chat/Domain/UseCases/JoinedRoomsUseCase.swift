//
//  JoinedRoomsUseCase.swift
//  OutPick
//
//  Created by Codex on 2/10/26.
//

import Foundation

protocol JoinedRoomsUseCaseProtocol {
    func fetchJoinedRooms(limit: Int?) async throws -> [JoinedRoomListItem]
    func fetchUnreadCount(roomID: String, lastMessageSeqHint: Int64?, lastMessageSenderUID: String?) async -> Int64
    func fetchReadSnapshot(roomID: String, lastMessageSeqHint: Int64?, lastMessageSenderUID: String?) async -> ChatRoomReadSnapshot?
    func canLeaveFromList(room: ChatRoom) -> Bool
    func leave(room: ChatRoom) async throws -> ChatRoomExitResult
}

final class JoinedRoomsUseCase: JoinedRoomsUseCaseProtocol {
    private let roomRepository: FirebaseChatRoomRepositoryProtocol
    private let userProfileRepository: UserProfileRepositoryProtocol
    private let exitUseCase: ChatRoomExitUseCaseProtocol

    init(
        roomRepository: FirebaseChatRoomRepositoryProtocol,
        userProfileRepository: UserProfileRepositoryProtocol,
        exitUseCase: ChatRoomExitUseCaseProtocol
    ) {
        self.roomRepository = roomRepository
        self.userProfileRepository = userProfileRepository
        self.exitUseCase = exitUseCase
    }

    func fetchJoinedRooms(limit: Int? = nil) async throws -> [JoinedRoomListItem] {
        let items = try await roomRepository.fetchJoinedRoomList(
            userUID: LoginManager.shared.canonicalUserID
        )
        guard let limit, limit > 0 else { return items }
        return Array(items.prefix(limit))
    }

    func fetchUnreadCount(roomID: String, lastMessageSeqHint: Int64?, lastMessageSenderUID: String?) async -> Int64 {
        guard let snapshot = await fetchReadSnapshot(
            roomID: roomID,
            lastMessageSeqHint: lastMessageSeqHint,
            lastMessageSenderUID: lastMessageSenderUID
        ) else {
            return 0
        }
        return snapshot.unreadCount(currentUserID: LoginManager.shared.canonicalUserID) ?? 0
    }

    func fetchReadSnapshot(roomID: String, lastMessageSeqHint: Int64?, lastMessageSenderUID: String?) async -> ChatRoomReadSnapshot? {
        do {
            let lastRead = try await userProfileRepository.fetchLastReadSeq(
                for: roomID,
                userUID: LoginManager.shared.canonicalUserID
            )
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
            return ChatRoomReadSnapshot(
                roomID: roomID,
                latestSeq: resolvedLatest,
                lastReadSeq: lastRead,
                lastMessageSenderUID: lastMessageSenderUID
            )
        } catch {
            print("⚠️ unread 계산 실패(roomID=\(roomID)): \(error)")
            return nil
        }
    }

    func canLeaveFromList(room: ChatRoom) -> Bool {
        room.creatorUID != LoginManager.shared.canonicalUserID
    }

    func leave(room: ChatRoom) async throws -> ChatRoomExitResult {
        try await exitUseCase.leaveOrClose(room: room)
    }
}
