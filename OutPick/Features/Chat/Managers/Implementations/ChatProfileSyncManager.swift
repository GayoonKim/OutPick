//
//  ChatProfileSyncManager.swift
//  OutPick
//
//  Created by Codex on 3/17/26.
//

import Foundation

final class ChatProfileSyncManager: ChatProfileSyncManaging {
    private let userProfileRepository: UserProfileRepositoryProtocol
    private let grdbManager: GRDBManager
    private let maxRefreshUIDs: Int

    private var cachedProfiles: [String: LocalUser] = [:]

    init(
        userProfileRepository: UserProfileRepositoryProtocol = FirebaseRepositoryProvider.shared.userProfileRepository,
        grdbManager: GRDBManager = .shared,
        maxRefreshUIDs: Int = 20
    ) {
        self.userProfileRepository = userProfileRepository
        self.grdbManager = grdbManager
        self.maxRefreshUIDs = max(1, maxRefreshUIDs)
    }

    @discardableResult
    func refreshProfiles(from messages: [ChatMessage]) async -> Set<String> {
        let senderIDs = recentSenderUIDs(from: messages)
        return await refreshProfiles(userIDs: senderIDs)
    }

    private func refreshProfiles(userIDs: Set<String>) async -> Set<String> {
        let normalizedUserIDs = Array(
            userIDs
                .map(normalizedUID)
                .filter { !$0.isEmpty && !$0.contains("/") }
                .prefix(maxRefreshUIDs)
        )
        guard !normalizedUserIDs.isEmpty else { return [] }

        do {
            let profilesByID = try await userProfileRepository.fetchUserProfiles(userIDs: normalizedUserIDs)
            var changedUserIDs = Set<String>()

            for userID in normalizedUserIDs {
                guard let fetchedProfile = profilesByID[userID] else { continue }
                let nextNickname = fetchedProfile.nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let nextAvatarPath = fetchedProfile.thumbPath
                let current = profile(for: userID)

                guard current?.nickname != nextNickname ||
                        current?.profileImagePath != nextAvatarPath else {
                    continue
                }

                let local = LocalUser(
                    email: userID,
                    nickname: nextNickname,
                    profileImagePath: nextAvatarPath
                )
                cachedProfiles[userID] = local
                changedUserIDs.insert(userID)

                _ = try grdbManager.upsertLocalUser(
                    email: userID,
                    nickname: nextNickname,
                    profileImagePath: nextAvatarPath
                )
            }

            return changedUserIDs
        } catch {
            print("⚠️ ChatProfileSyncManager profile refresh failed:", error)
            return []
        }
    }

    func profile(for senderUID: String) -> LocalUser? {
        let senderUID = normalizedUID(senderUID)
        guard !senderUID.isEmpty else { return nil }

        if let cached = cachedProfiles[senderUID] {
            return cached
        }

        if let local = try? grdbManager.fetchLocalUser(email: senderUID) {
            cachedProfiles[senderUID] = local
            return local
        }

        return nil
    }

    func reset() {
        cachedProfiles.removeAll()
    }

    private func recentSenderUIDs(from messages: [ChatMessage]) -> Set<String> {
        var result: [String] = []
        var seen = Set<String>()

        for message in messages.sorted(by: { ($0.sentAt ?? .distantPast) > ($1.sentAt ?? .distantPast) }) {
            let senderUID = normalizedUID(message.senderUID)
            guard !senderUID.isEmpty,
                  !senderUID.contains("/"),
                  seen.insert(senderUID).inserted else {
                continue
            }
            result.append(senderUID)
            if result.count >= maxRefreshUIDs { break }
        }

        return Set(result)
    }

    private func normalizedUID(_ uid: String) -> String {
        uid.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
