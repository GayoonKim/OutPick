//
//  ChatProfileSyncManager.swift
//  OutPick
//
//  Created by Codex on 3/17/26.
//

import Foundation

final class ChatProfileSyncManager: ChatProfileSyncManaging {
    private let maxRefreshUIDs: Int
    private let cacheActor: ChatProfileCacheActor

    @MainActor
    private var profileSnapshot: [String: LocalChatUser] = [:]
    @MainActor
    private var snapshotGeneration: Int = 0

    init(
        userProfileRepository: UserProfileRepositoryProtocol = FirebaseRepositoryProvider.shared.userProfileRepository,
        profileCache: ChatProfileCachePersisting,
        maxRefreshUIDs: Int = 20
    ) {
        self.maxRefreshUIDs = max(1, maxRefreshUIDs)
        self.cacheActor = ChatProfileCacheActor(
            userProfileRepository: userProfileRepository,
            profileCache: profileCache
        )
    }

    @discardableResult
    func refreshProfiles(from messages: [ChatMessage]) async -> Set<String> {
        let senderIDs = recentSenderUIDs(from: messages)
        return await refreshProfiles(userIDs: Array(senderIDs))
    }

    private func refreshProfiles(userIDs: [String]) async -> Set<String> {
        let normalizedUserIDs = Array(
            userIDs
                .map(normalizedUID)
                .filter { !$0.isEmpty && !$0.contains("/") }
                .prefix(maxRefreshUIDs)
        )
        guard !normalizedUserIDs.isEmpty else { return [] }

        let generation = await MainActor.run { snapshotGeneration }
        let refreshedProfiles = await cacheActor.refreshProfiles(userIDs: normalizedUserIDs)
        guard !refreshedProfiles.isEmpty else { return [] }

        return await MainActor.run {
            guard generation == snapshotGeneration else { return [] }

            var changedUserIDs = Set<String>()
            for (userID, profile) in refreshedProfiles {
                let current = profileSnapshot[userID]
                if current?.nickname != profile.nickname ||
                    current?.profileImagePath != profile.profileImagePath {
                    changedUserIDs.insert(userID)
                }
                profileSnapshot[userID] = profile
            }

            return changedUserIDs
        }
    }

    @MainActor
    func profile(for senderUID: String) -> LocalChatUser? {
        let senderUID = normalizedUID(senderUID)
        guard !senderUID.isEmpty else { return nil }
        return profileSnapshot[senderUID]
    }

    @MainActor
    func reset() {
        snapshotGeneration += 1
        profileSnapshot.removeAll()
        Task { [cacheActor] in
            await cacheActor.reset()
        }
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

private actor ChatProfileCacheActor {
    private let userProfileRepository: UserProfileRepositoryProtocol
    private let profileCache: ChatProfileCachePersisting
    private var cachedProfiles: [String: LocalChatUser] = [:]
    private var generation: Int = 0

    init(
        userProfileRepository: UserProfileRepositoryProtocol,
        profileCache: ChatProfileCachePersisting
    ) {
        self.userProfileRepository = userProfileRepository
        self.profileCache = profileCache
    }

    func refreshProfiles(userIDs: [String]) async -> [String: LocalChatUser] {
        let generationAtStart = generation

        do {
            let profilesByID = try await userProfileRepository.fetchUserProfiles(userIDs: userIDs)
            guard generationAtStart == generation else { return [:] }

            var refreshedProfiles: [String: LocalChatUser] = [:]
            for userID in userIDs {
                guard let fetchedProfile = profilesByID[userID] else { continue }
                let local = LocalChatUser(
                    userID: userID,
                    nickname: fetchedProfile.nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                    profileImagePath: fetchedProfile.thumbPath
                )

                refreshedProfiles[userID] = local
                let current = cachedProfiles[userID] ?? (try? profileCache.fetchLocalChatUser(userID: userID))
                cachedProfiles[userID] = local

                guard current?.nickname != local.nickname ||
                    current?.profileImagePath != local.profileImagePath else {
                    continue
                }

                _ = try profileCache.upsertLocalChatUser(
                    userID: userID,
                    nickname: local.nickname,
                    profileImagePath: local.profileImagePath
                )
            }

            return refreshedProfiles
        } catch {
            print("⚠️ ChatProfileSyncManager profile refresh failed:", error)
            return [:]
        }
    }

    func reset() {
        generation += 1
        cachedProfiles.removeAll()
    }
}
