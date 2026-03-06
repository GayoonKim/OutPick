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
    func loadInitial(room: ChatRoom) async throws -> ChatRoomParticipantsLoadResult
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

    func loadInitial(room: ChatRoom) async throws -> ChatRoomParticipantsLoadResult {
        let roomID = room.ID ?? ""
        resetState(for: roomID)

        var (page, total) = try participantsRepository.fetchLocalUsersPage(
            roomID: roomID,
            offset: 0,
            limit: pageSize
        )

        loadedParticipantEmails = Set(page.map(\.email))

        try await fillParticipantsFromServerIfNeeded(
            room: room,
            roomID: roomID,
            currentCount: page.count,
            targetCount: pageSize
        )

        (page, total) = try participantsRepository.fetchLocalUsersPage(
            roomID: roomID,
            offset: 0,
            limit: pageSize
        )

        loadedParticipantEmails = Set(page.map(\.email))
        nextOffset = page.count
        hasMore = total > page.count

        return ChatRoomParticipantsLoadResult(users: page, hasMore: hasMore)
    }

    func loadMore(room: ChatRoom) async throws -> ChatRoomParticipantsLoadResult {
        let roomID = room.ID ?? ""
        guard activeRoomID == roomID else {
            return try await loadInitial(room: room)
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
        var deduped = page.filter { !loadedParticipantEmails.contains($0.email) }

        if deduped.count < pageSize {
            try await fillParticipantsFromServerIfNeeded(
                room: room,
                roomID: roomID,
                currentCount: loadedParticipantEmails.count,
                targetCount: loadedParticipantEmails.count + (pageSize - deduped.count)
            )
            (page, total) = try participantsRepository.fetchLocalUsersPage(
                roomID: roomID,
                offset: currentOffset,
                limit: pageSize
            )
            deduped = page.filter { !loadedParticipantEmails.contains($0.email) }
        }

        if !deduped.isEmpty {
            nextOffset += deduped.count
            loadedParticipantEmails.formUnion(deduped.map(\.email))
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

    private func fillParticipantsFromServerIfNeeded(
        room: ChatRoom,
        roomID: String,
        currentCount: Int,
        targetCount: Int
    ) async throws {
        let allParticipants = Set(room.participants)
        let desiredCount = min(targetCount, allParticipants.count)
        guard currentCount < desiredCount else { return }

        let missing = Array(allParticipants.subtracting(loadedParticipantEmails))
        let need = min(desiredCount - currentCount, missing.count)
        guard need > 0 else { return }

        let profiles = try await userProfileRepository.fetchUserProfiles(emails: Array(missing.prefix(need)))

        for profile in profiles {
            let email = profile.email
            guard !email.isEmpty else { continue }
            try participantsRepository.upsertLocalUser(
                email: email,
                nickname: profile.nickname ?? "",
                profileImagePath: profile.thumbPath
            )
            try participantsRepository.addLocalUser(email, toRoom: roomID)
        }
    }
}
