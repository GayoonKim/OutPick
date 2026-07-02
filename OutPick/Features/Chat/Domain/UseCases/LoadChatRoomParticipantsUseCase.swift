//
//  LoadChatRoomParticipantsUseCase.swift
//  OutPick
//
//  Created by Codex on 3/7/26.
//

import Foundation

struct ChatRoomParticipantsLoadResult {
    let users: [LocalUser]
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
    private let pageSize: Int

    private var activeRoomID: String?
    private var hasMore: Bool = true
    private var loadedParticipantUIDs: Set<String> = []

    init(
        participantsRepository: ChatRoomParticipantsRepositoryProtocol,
        userProfileRepository: UserProfileRepositoryProtocol,
        pageSize: Int = 50
    ) {
        self.participantsRepository = participantsRepository
        self.userProfileRepository = userProfileRepository
        self.pageSize = pageSize
    }

    func loadLocalInitial(room: ChatRoom) throws -> ChatRoomParticipantsLoadResult {
        let roomID = room.ID ?? ""
        resetState(for: roomID)
        try reconcileMembership(room: room, roomID: roomID)

        let (page, total) = try participantsRepository.fetchLocalUsersPage(
            roomID: roomID,
            offset: 0,
            limit: pageSize
        )

        loadedParticipantUIDs = Set(page.map { normalizedUID($0.email) })
        hasMore = total > loadedParticipantUIDs.count

        return ChatRoomParticipantsLoadResult(users: page, hasMore: hasMore)
    }

    func reconcileInitial(room: ChatRoom) async throws -> ChatRoomParticipantsLoadResult {
        let roomID = room.ID ?? ""
        if activeRoomID != roomID {
            _ = try loadLocalInitial(room: room)
        }

        try reconcileMembership(room: room, roomID: roomID)
        // 첫 번째 갱신으로 정렬이 바뀌면 placeholder 사용자가 상단 페이지로 다시 올라올 수 있어
        // 한 번 더 현재 첫 페이지를 새로고쳐 visible section의 신선도를 높인다.
        try await refreshProfilesForVisiblePage(roomID: roomID, offset: 0, limit: pageSize)
        try await refreshProfilesForVisiblePage(roomID: roomID, offset: 0, limit: pageSize)

        let (page, total) = try participantsRepository.fetchLocalUsersPage(
            roomID: roomID,
            offset: 0,
            limit: pageSize
        )

        loadedParticipantUIDs = Set(page.map { normalizedUID($0.email) })
        hasMore = total > loadedParticipantUIDs.count

        return ChatRoomParticipantsLoadResult(users: page, hasMore: hasMore)
    }

    func loadMore(room: ChatRoom) async throws -> ChatRoomParticipantsLoadResult {
        let roomID = room.ID ?? ""
        guard activeRoomID == roomID else {
            _ = try loadLocalInitial(room: room)
            return ChatRoomParticipantsLoadResult(users: [], hasMore: hasMore)
        }
        guard hasMore else {
            return ChatRoomParticipantsLoadResult(users: [], hasMore: false)
        }

        try reconcileMembership(room: room, roomID: roomID)

        var allUsers = try participantsRepository.fetchLocalUsers(in: roomID)
        var nextUsers = nextUsersForDisplay(from: allUsers)

        if nextUsers.isEmpty {
            let authoritativeCount = authoritativeParticipantUIDs(for: room).count
            if allUsers.count < authoritativeCount {
                try fillParticipantsFromServerIfNeeded(
                    room: room,
                    roomID: roomID,
                    targetCount: authoritativeCount
                )
                allUsers = try participantsRepository.fetchLocalUsers(in: roomID)
                nextUsers = nextUsersForDisplay(from: allUsers)
            }
        }

        if !nextUsers.isEmpty {
            try await refreshProfiles(userIDs: nextUsers.map(\.email))
            allUsers = try participantsRepository.fetchLocalUsers(in: roomID)
            nextUsers = nextUsersForDisplay(from: allUsers)
        }

        loadedParticipantUIDs.formUnion(nextUsers.map { normalizedUID($0.email) })
        hasMore = loadedParticipantUIDs.count < allUsers.count

        return ChatRoomParticipantsLoadResult(users: nextUsers, hasMore: hasMore)
    }

    private func resetState(for roomID: String) {
        activeRoomID = roomID
        hasMore = true
        loadedParticipantUIDs = []
    }

    private func nextUsersForDisplay(from users: [LocalUser]) -> [LocalUser] {
        Array(
            users.lazy
                .filter { !self.loadedParticipantUIDs.contains(self.normalizedUID($0.email)) }
                .prefix(pageSize)
        )
    }

    private func reconcileMembership(room: ChatRoom, roomID: String) throws {
        let authoritativeParticipants = authoritativeParticipantUIDs(for: room)
        let localParticipantUIDs = try participantsRepository.userEmails(in: roomID)
        let localParticipantsByNormalized = Dictionary(grouping: localParticipantUIDs, by: normalizedUID)
        let localParticipants = Set(localParticipantsByNormalized.keys)

        let removedParticipants = localParticipants.subtracting(authoritativeParticipants).sorted()
        for normalized in removedParticipants {
            for rawUID in localParticipantsByNormalized[normalized] ?? [] {
                try participantsRepository.removeLocalUser(rawUID, fromRoom: roomID)
            }
        }

        for normalized in authoritativeParticipants {
            let rawUIDs = localParticipantsByNormalized[normalized] ?? []
            let nonCanonicalUIDs = rawUIDs.filter { $0 != normalized }
            for rawUID in nonCanonicalUIDs {
                try participantsRepository.removeLocalUser(rawUID, fromRoom: roomID)
            }
        }

        // RoomMember만 있고 LocalUser가 없는 상태도 화면에서 누락되지 않도록,
        // authoritative participant 전원에 대해 멤버십 + 최소 LocalUser row를 보장한다.
        let requiredParticipants = Array(authoritativeParticipants).sorted()
        try attachPlaceholderParticipants(requiredParticipants, toRoom: roomID)
    }

    private func fillParticipantsFromServerIfNeeded(
        room: ChatRoom,
        roomID: String,
        targetCount: Int
    ) throws {
        let authoritativeParticipants = authoritativeParticipantUIDs(for: room)
        let localParticipants = Set(
            try participantsRepository.userEmails(in: roomID).map { normalizedUID($0) }
        )
        let desiredCount = min(targetCount, authoritativeParticipants.count)
        guard localParticipants.count < desiredCount else { return }

        let missingParticipants = Array(authoritativeParticipants.subtracting(localParticipants)).sorted()
        let need = min(desiredCount - localParticipants.count, missingParticipants.count)
        guard need > 0 else { return }

        try attachPlaceholderParticipants(Array(missingParticipants.prefix(need)), toRoom: roomID)
    }

    private func attachPlaceholderParticipants(
        _ uids: [String],
        toRoom roomID: String
    ) throws {
        let normalizedUIDs = uniqueNormalizedUIDs(from: uids)
        guard !normalizedUIDs.isEmpty else { return }

        for uid in normalizedUIDs {
            let existingLocalUser = try participantsRepository.fetchLocalUser(email: uid)
            let nickname = resolvedNickname(
                uid: uid,
                fetchedNickname: nil,
                existingNickname: existingLocalUser?.nickname,
                allowPlaceholder: true
            )
            let profileImagePath = existingLocalUser?.profileImagePath

            if let nickname {
                try participantsRepository.upsertLocalUser(
                    email: uid,
                    nickname: nickname,
                    profileImagePath: profileImagePath
                )
            }
            try participantsRepository.addLocalUser(uid, toRoom: roomID)
        }
    }

    private func refreshProfilesForVisiblePage(roomID: String, offset: Int, limit: Int) async throws {
        let (page, _) = try participantsRepository.fetchLocalUsersPage(
            roomID: roomID,
            offset: offset,
            limit: limit
        )
        try await refreshProfiles(userIDs: page.map(\.email))
    }

    private func refreshProfiles(userIDs: [String]) async throws {
        let normalizedUserIDs = uniqueNormalizedUIDs(from: userIDs)
        guard !normalizedUserIDs.isEmpty else { return }

        let profilesByUserID = try await userProfileRepository.fetchUserProfiles(userIDs: normalizedUserIDs)

        for userID in normalizedUserIDs {
            guard let profile = profilesByUserID[userID] else { continue }

            let existingLocalUser = try participantsRepository.fetchLocalUser(email: userID)
            let nickname = resolvedNickname(
                uid: userID,
                fetchedNickname: profile.nickname,
                existingNickname: existingLocalUser?.nickname,
                allowPlaceholder: false
            )
            guard let nickname else { continue }

            let nextProfileImagePath = profile.thumbPath ?? existingLocalUser?.profileImagePath
            guard existingLocalUser?.nickname != nickname ||
                    existingLocalUser?.profileImagePath != nextProfileImagePath else {
                continue
            }

            try participantsRepository.upsertLocalUser(
                email: userID,
                nickname: nickname,
                profileImagePath: nextProfileImagePath
            )
        }
    }

    private func authoritativeParticipantUIDs(for room: ChatRoom) -> Set<String> {
        Set(uniqueNormalizedUIDs(from: room.participants))
    }

    private func uniqueNormalizedUIDs(from uids: [String]) -> [String] {
        var seen = Set<String>()
        return uids.compactMap { raw in
            let uid = normalizedUID(raw)
            guard !uid.isEmpty, !uid.contains("/"), seen.insert(uid).inserted else { return nil }
            return uid
        }
    }

    private func resolvedNickname(
        uid: String,
        fetchedNickname: String?,
        existingNickname: String?,
        allowPlaceholder: Bool
    ) -> String? {
        let fetched = fetchedNickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !fetched.isEmpty {
            return fetched
        }

        let existing = existingNickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !existing.isEmpty {
            return existing
        }

        return allowPlaceholder ? uid : nil
    }

    private func normalizedUID(_ uid: String) -> String {
        uid.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
