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
    private var nextOffset: Int = 0
    private var hasMore: Bool = true
    private var loadedParticipantEmails: Set<String> = []

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

        let (page, total) = try participantsRepository.fetchLocalUsersPage(
            roomID: roomID,
            offset: 0,
            limit: pageSize
        )

        loadedParticipantEmails = Set(page.map { normalizedEmail($0.email) })
        nextOffset = page.count
        hasMore = total > page.count

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

        loadedParticipantEmails = Set(page.map { normalizedEmail($0.email) })
        nextOffset = page.count
        hasMore = total > page.count

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

        let currentOffset = nextOffset
        var (page, total) = try participantsRepository.fetchLocalUsersPage(
            roomID: roomID,
            offset: currentOffset,
            limit: pageSize
        )
        var deduped = page.filter { !loadedParticipantEmails.contains(normalizedEmail($0.email)) }

        if deduped.count < pageSize {
            try fillParticipantsFromServerIfNeeded(
                room: room,
                roomID: roomID,
                targetCount: currentOffset + pageSize
            )
            (page, total) = try participantsRepository.fetchLocalUsersPage(
                roomID: roomID,
                offset: currentOffset,
                limit: pageSize
            )
            deduped = page.filter { !loadedParticipantEmails.contains(normalizedEmail($0.email)) }
        }

        if !deduped.isEmpty {
            try await refreshProfiles(emails: deduped.map(\.email))
            (page, total) = try participantsRepository.fetchLocalUsersPage(
                roomID: roomID,
                offset: currentOffset,
                limit: pageSize
            )
            deduped = page.filter { !loadedParticipantEmails.contains(normalizedEmail($0.email)) }
        }

        if !deduped.isEmpty {
            nextOffset += deduped.count
            loadedParticipantEmails.formUnion(deduped.map { normalizedEmail($0.email) })
        }
        hasMore = nextOffset < total

        return ChatRoomParticipantsLoadResult(users: deduped, hasMore: hasMore)
    }

    private func resetState(for roomID: String) {
        activeRoomID = roomID
        nextOffset = 0
        hasMore = true
        loadedParticipantEmails = []
    }

    private func reconcileMembership(room: ChatRoom, roomID: String) throws {
        let authoritativeParticipants = authoritativeParticipantEmails(for: room)
        let localParticipants = Set(
            try participantsRepository.userEmails(in: roomID).map { normalizedEmail($0) }
        )

        let removedParticipants = localParticipants.subtracting(authoritativeParticipants).sorted()
        for email in removedParticipants {
            try participantsRepository.removeLocalUser(email, fromRoom: roomID)
        }

        let missingParticipants = Array(authoritativeParticipants.subtracting(localParticipants)).sorted()
        try attachPlaceholderParticipants(missingParticipants, toRoom: roomID)
    }

    private func fillParticipantsFromServerIfNeeded(
        room: ChatRoom,
        roomID: String,
        targetCount: Int
    ) throws {
        let authoritativeParticipants = authoritativeParticipantEmails(for: room)
        let localParticipants = Set(
            try participantsRepository.userEmails(in: roomID).map { normalizedEmail($0) }
        )
        let desiredCount = min(targetCount, authoritativeParticipants.count)
        guard localParticipants.count < desiredCount else { return }

        let missingParticipants = Array(authoritativeParticipants.subtracting(localParticipants)).sorted()
        let need = min(desiredCount - localParticipants.count, missingParticipants.count)
        guard need > 0 else { return }

        try attachPlaceholderParticipants(Array(missingParticipants.prefix(need)), toRoom: roomID)
    }

    private func attachPlaceholderParticipants(
        _ emails: [String],
        toRoom roomID: String
    ) throws {
        let normalizedEmails = uniqueNormalizedEmails(from: emails)
        guard !normalizedEmails.isEmpty else { return }

        for email in normalizedEmails {
            let existingLocalUser = try participantsRepository.fetchLocalUser(email: email)
            let nickname = resolvedNickname(
                email: email,
                fetchedNickname: nil,
                existingNickname: existingLocalUser?.nickname,
                allowPlaceholder: true
            )
            let profileImagePath = existingLocalUser?.profileImagePath

            if let nickname {
                try participantsRepository.upsertLocalUser(
                    email: email,
                    nickname: nickname,
                    profileImagePath: profileImagePath
                )
            }
            try participantsRepository.addLocalUser(email, toRoom: roomID)
        }
    }

    private func refreshProfilesForVisiblePage(roomID: String, offset: Int, limit: Int) async throws {
        let (page, _) = try participantsRepository.fetchLocalUsersPage(
            roomID: roomID,
            offset: offset,
            limit: limit
        )
        try await refreshProfiles(emails: page.map(\.email))
    }

    private func refreshProfiles(emails: [String]) async throws {
        let normalizedEmails = uniqueNormalizedEmails(from: emails)
        guard !normalizedEmails.isEmpty else { return }

        let fetchedProfiles = try await userProfileRepository.fetchUserProfiles(emails: normalizedEmails)
        let profilesByEmail = Dictionary(
            uniqueKeysWithValues: fetchedProfiles.map { (normalizedEmail($0.email), $0) }
        )

        for email in normalizedEmails {
            guard let profile = profilesByEmail[email] else { continue }

            let existingLocalUser = try participantsRepository.fetchLocalUser(email: email)
            let nickname = resolvedNickname(
                email: email,
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
                email: email,
                nickname: nickname,
                profileImagePath: nextProfileImagePath
            )
        }
    }

    private func authoritativeParticipantEmails(for room: ChatRoom) -> Set<String> {
        Set(uniqueNormalizedEmails(from: room.participants))
    }

    private func uniqueNormalizedEmails(from emails: [String]) -> [String] {
        var seen = Set<String>()
        return emails.compactMap { raw in
            let email = normalizedEmail(raw)
            guard !email.isEmpty, seen.insert(email).inserted else { return nil }
            return email
        }
    }

    private func resolvedNickname(
        email: String,
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

        return allowPlaceholder ? email : nil
    }

    private func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
