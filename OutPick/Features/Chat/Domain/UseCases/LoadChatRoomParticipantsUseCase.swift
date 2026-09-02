//
//  LoadChatRoomParticipantsUseCase.swift
//  OutPick
//
//  Created by Codex on 3/7/26.
//

import Foundation

struct ChatRoomParticipantsLoadResult {
    let participants: [ChatRoomParticipant]
    let hasMore: Bool

    var users: [LocalChatUser] { participants.map(\.user) }

    init(participants: [ChatRoomParticipant], hasMore: Bool) {
        self.participants = participants
        self.hasMore = hasMore
    }

    init(users: [LocalChatUser], hasMore: Bool) {
        self.init(
            participants: users.map {
                ChatRoomParticipant(user: $0, role: .member, moderatorSince: nil)
            },
            hasMore: hasMore
        )
    }
}

struct ChatRoomParticipant: Hashable {
    let user: LocalChatUser
    var role: ChatRoomMemberRole
    var moderatorSince: Date?

    var userID: String { user.userID }
}

enum ChatRoomParticipantOrdering {
    static func deduplicatedAndSorted(
        _ participants: [ChatRoomParticipant],
        currentUserID: String,
        ownerUID: String
    ) -> [ChatRoomParticipant] {
        var byUserID: [String: ChatRoomParticipant] = [:]
        for participant in participants {
            if let existing = byUserID[participant.userID],
               roleRank(existing.role) > roleRank(participant.role) {
                continue
            }
            byUserID[participant.userID] = participant
        }
        return sorted(
            Array(byUserID.values),
            currentUserID: currentUserID,
            ownerUID: ownerUID
        )
    }

    static func sorted(
        _ participants: [ChatRoomParticipant],
        currentUserID: String,
        ownerUID: String
    ) -> [ChatRoomParticipant] {
        participants.sorted { lhs, rhs in
            let lhsRank = rank(lhs, currentUserID: currentUserID, ownerUID: ownerUID)
            let rhsRank = rank(rhs, currentUserID: currentUserID, ownerUID: ownerUID)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if lhs.role == .moderator, rhs.role == .moderator {
                let lhsDate = lhs.moderatorSince ?? .distantFuture
                let rhsDate = rhs.moderatorSince ?? .distantFuture
                if lhsDate != rhsDate { return lhsDate < rhsDate }
            }
            return lhs.userID < rhs.userID
        }
    }

    private static func rank(
        _ participant: ChatRoomParticipant,
        currentUserID: String,
        ownerUID: String
    ) -> Int {
        if participant.userID == currentUserID { return 0 }
        if participant.userID == ownerUID || participant.role == .owner { return 1 }
        if participant.role == .moderator { return 2 }
        return 3
    }

    private static func roleRank(_ role: ChatRoomMemberRole) -> Int {
        switch role {
        case .owner: return 3
        case .moderator: return 2
        case .member: return 1
        }
    }
}

@MainActor
protocol LoadChatRoomParticipantsUseCaseProtocol {
    func loadLocalInitial(room: ChatRoom) throws -> ChatRoomParticipantsLoadResult
    func reconcileInitial(room: ChatRoom) async throws -> ChatRoomParticipantsLoadResult
    func loadMore(room: ChatRoom) async throws -> ChatRoomParticipantsLoadResult
}

@MainActor
final class LoadChatRoomParticipantsUseCase: LoadChatRoomParticipantsUseCaseProtocol {
    private let participantsRepository: ChatRoomParticipantsRepositoryProtocol
    private let publicProfileRepository: UserPublicProfileRepositoryProtocol
    private let chatRoomRepository: FirebaseChatRoomRepositoryProtocol
    private let currentUserID: () -> String
    private let pageSize: Int

    private var activeRoomID: String?
    private var nextCursorUserID: String?
    private var hasMore: Bool = true
    private var loadedParticipantUIDs: Set<String> = []

    init(
        participantsRepository: ChatRoomParticipantsRepositoryProtocol,
        publicProfileRepository: UserPublicProfileRepositoryProtocol,
        chatRoomRepository: FirebaseChatRoomRepositoryProtocol,
        currentUserID: @escaping () -> String = { LoginManager.shared.canonicalUserID },
        pageSize: Int = 50
    ) {
        self.participantsRepository = participantsRepository
        self.publicProfileRepository = publicProfileRepository
        self.chatRoomRepository = chatRoomRepository
        self.currentUserID = currentUserID
        self.pageSize = max(1, pageSize)
    }

    func loadLocalInitial(room: ChatRoom) throws -> ChatRoomParticipantsLoadResult {
        let roomID = normalizedID(room.id)
        resetState(for: roomID)
        return ChatRoomParticipantsLoadResult(participants: [], hasMore: !roomID.isEmpty)
    }

    func reconcileInitial(room: ChatRoom) async throws -> ChatRoomParticipantsLoadResult {
        let roomID = normalizedID(room.id)
        resetState(for: roomID)
        guard !roomID.isEmpty else {
            return ChatRoomParticipantsLoadResult(participants: [], hasMore: false)
        }
        let pinned = try await chatRoomRepository.fetchPinnedRoomMembers(
            roomID: roomID,
            currentUserID: currentUserID(),
            ownerUID: room.ownerUID
        )
        let page = try await loadRemotePage(roomID: roomID, afterUserID: nil)
        let pinnedParticipants = try await materializeParticipants(members: pinned)
        let combined = mergeAndSort(
            pinnedParticipants + page.participants,
            ownerUID: room.ownerUID
        )
        return ChatRoomParticipantsLoadResult(participants: combined, hasMore: page.hasMore)
    }

    func loadMore(room: ChatRoom) async throws -> ChatRoomParticipantsLoadResult {
        let roomID = normalizedID(room.id)
        guard !roomID.isEmpty else {
            resetState(for: roomID)
            return ChatRoomParticipantsLoadResult(participants: [], hasMore: false)
        }
        if activeRoomID != roomID {
            resetState(for: roomID)
        }
        guard hasMore else {
            return ChatRoomParticipantsLoadResult(participants: [], hasMore: false)
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

        let uniqueMembers = uniqueMembers(from: page.members)
            .filter { loadedParticipantUIDs.insert($0.userID).inserted }
        let participants = try await materializeParticipants(members: uniqueMembers)

        return ChatRoomParticipantsLoadResult(participants: participants, hasMore: hasMore)
    }

    private func materializeParticipants(members: [RoomMemberSummary]) async throws -> [ChatRoomParticipant] {
        let userIDs = members.map(\.userID)
        guard !userIDs.isEmpty else { return [] }

        let profilesByUserID = try await publicProfileRepository.fetchProfiles(userIDs: userIDs)
        var participants: [ChatRoomParticipant] = []
        participants.reserveCapacity(userIDs.count)

        for member in members {
            let userID = member.userID
            let profile = profilesByUserID[userID]
            let existingLocalUser = try participantsRepository.fetchLocalChatUser(userID: userID)
            let nickname = resolvedNickname(
                uid: userID,
                fetchedNickname: profile?.nickname,
                existingNickname: existingLocalUser?.nickname
            )
            let profileImagePath = profile?.avatarThumbPath ?? existingLocalUser?.profileImagePath
            let displayUser = LocalChatUser(
                userID: userID,
                nickname: nickname ?? "알 수 없는 사용자",
                profileImagePath: profileImagePath
            )
            participants.append(ChatRoomParticipant(
                user: displayUser,
                role: member.role,
                moderatorSince: member.moderatorSince
            ))

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

        return participants
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

    private func uniqueMembers(from members: [RoomMemberSummary]) -> [RoomMemberSummary] {
        var seen = Set<String>()
        return members.compactMap { member in
            let uid = normalizedID(member.userID)
            guard !uid.isEmpty, !uid.contains("/"), seen.insert(uid).inserted else { return nil }
            return RoomMemberSummary(
                userID: uid,
                role: member.role,
                moderatorSince: member.moderatorSince
            )
        }
    }

    private func mergeAndSort(
        _ participants: [ChatRoomParticipant],
        ownerUID: String
    ) -> [ChatRoomParticipant] {
        return ChatRoomParticipantOrdering.deduplicatedAndSorted(
            participants,
            currentUserID: normalizedID(currentUserID()),
            ownerUID: normalizedID(ownerUID)
        )
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
