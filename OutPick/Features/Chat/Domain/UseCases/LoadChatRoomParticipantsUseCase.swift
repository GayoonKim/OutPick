//
//  LoadChatRoomParticipantsUseCase.swift
//  OutPick
//
//  Created by Codex on 3/7/26.
//

import Foundation

struct ChatRoomParticipantsLoadResult {
    let users: [LocalChatUser]
    let hasMore: Bool
}

protocol LoadChatRoomParticipantsUseCaseProtocol {
    func loadLocalInitial(room: ChatRoom) throws -> ChatRoomParticipantsLoadResult
    func reconcileInitial(room: ChatRoom) async throws -> ChatRoomParticipantsLoadResult
    func loadMore(room: ChatRoom) async throws -> ChatRoomParticipantsLoadResult
}

@MainActor
final class LoadChatRoomParticipantsUseCase: LoadChatRoomParticipantsUseCaseProtocol {
    private let participantsRepository: ChatRoomParticipantsRepositoryProtocol
    private let userProfileRepository: UserProfileRepositoryProtocol
    private let chatRoomRepository: FirebaseChatRoomRepositoryProtocol
    private let pageSize: Int

    private var activeRoomID: String?
    private var nextCursorUserID: String?
    private var hasMore: Bool = true
    private var loadedParticipantUIDs: Set<String> = []

    init(
        participantsRepository: ChatRoomParticipantsRepositoryProtocol,
        userProfileRepository: UserProfileRepositoryProtocol,
        chatRoomRepository: FirebaseChatRoomRepositoryProtocol,
        pageSize: Int = 50
    ) {
        self.participantsRepository = participantsRepository
        self.userProfileRepository = userProfileRepository
        self.chatRoomRepository = chatRoomRepository
        self.pageSize = max(1, pageSize)
    }

    func loadLocalInitial(room: ChatRoom) throws -> ChatRoomParticipantsLoadResult {
        let roomID = normalizedID(room.ID ?? "")
        resetState(for: roomID)
        return ChatRoomParticipantsLoadResult(users: [], hasMore: !roomID.isEmpty)
    }

    func reconcileInitial(room: ChatRoom) async throws -> ChatRoomParticipantsLoadResult {
        let roomID = normalizedID(room.ID ?? "")
        resetState(for: roomID)
        guard !roomID.isEmpty else {
            return ChatRoomParticipantsLoadResult(users: [], hasMore: false)
        }

        return try await loadRemotePage(roomID: roomID, afterUserID: nil)
    }

    func loadMore(room: ChatRoom) async throws -> ChatRoomParticipantsLoadResult {
        let roomID = normalizedID(room.ID ?? "")
        guard !roomID.isEmpty else {
            resetState(for: roomID)
            return ChatRoomParticipantsLoadResult(users: [], hasMore: false)
        }
        if activeRoomID != roomID {
            resetState(for: roomID)
        }
        guard hasMore else {
            return ChatRoomParticipantsLoadResult(users: [], hasMore: false)
        }

        return try await loadRemotePage(roomID: roomID, afterUserID: nextCursorUserID)
    }

    private func resetState(for roomID: String) {
        activeRoomID = roomID
        nextCursorUserID = nil
        hasMore = true
        loadedParticipantUIDs = []
    }

    private func loadRemotePage(roomID: String, afterUserID: String?) async throws -> ChatRoomParticipantsLoadResult {
        let page = try await chatRoomRepository.fetchRoomMembersPage(
            roomID: roomID,
            limit: pageSize,
            afterUserID: afterUserID
        )
        nextCursorUserID = page.nextCursorUserID
        hasMore = page.hasMore

        let pageUserIDs = uniqueNormalizedUIDs(from: page.userIDs)
            .filter { loadedParticipantUIDs.insert($0).inserted }
        let users = try await materializeUsers(userIDs: pageUserIDs)

        return ChatRoomParticipantsLoadResult(users: users, hasMore: hasMore)
    }

    private func materializeUsers(userIDs: [String]) async throws -> [LocalChatUser] {
        guard !userIDs.isEmpty else { return [] }

        let profilesByUserID = try await userProfileRepository.fetchUserProfiles(userIDs: userIDs)
        var users: [LocalChatUser] = []
        users.reserveCapacity(userIDs.count)

        for userID in userIDs {
            let profile = profilesByUserID[userID]
            let existingLocalUser = try participantsRepository.fetchLocalChatUser(userID: userID)
            let nickname = resolvedNickname(
                uid: userID,
                fetchedNickname: profile?.nickname,
                existingNickname: existingLocalUser?.nickname
            )
            let profileImagePath = profile?.thumbPath ?? existingLocalUser?.profileImagePath
            let displayUser = LocalChatUser(
                userID: userID,
                nickname: nickname ?? "알 수 없는 사용자",
                profileImagePath: profileImagePath
            )
            users.append(displayUser)

            guard shouldPersistLocalUser(
                displayUser,
                resolvedNickname: nickname,
                existingLocalUser: existingLocalUser
            ) else {
                continue
            }

            try participantsRepository.upsertLocalChatUser(
                userID: displayUser.userID,
                nickname: displayUser.nickname,
                profileImagePath: displayUser.profileImagePath
            )
        }

        return users
    }

    private func shouldPersistLocalUser(
        _ displayUser: LocalChatUser,
        resolvedNickname: String?,
        existingLocalUser: LocalChatUser?
    ) -> Bool {
        guard resolvedNickname != nil || displayUser.profileImagePath != nil else { return false }
        return existingLocalUser?.nickname != displayUser.nickname ||
            existingLocalUser?.profileImagePath != displayUser.profileImagePath
    }

    private func uniqueNormalizedUIDs(from uids: [String]) -> [String] {
        var seen = Set<String>()
        return uids.compactMap { raw in
            let uid = normalizedID(raw)
            guard !uid.isEmpty, !uid.contains("/"), seen.insert(uid).inserted else { return nil }
            return uid
        }
    }

    private func resolvedNickname(
        uid: String,
        fetchedNickname: String?,
        existingNickname: String?
    ) -> String? {
        let fetched = fetchedNickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !fetched.isEmpty {
            return fetched
        }

        let existing = existingNickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !existing.isEmpty, normalizedID(existing) != normalizedID(uid) {
            return existing
        }

        return nil
    }

    private func normalizedID(_ id: String) -> String {
        id.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
