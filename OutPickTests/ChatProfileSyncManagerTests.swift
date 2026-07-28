//
//  ChatProfileSyncManagerTests.swift
//  OutPickTests
//
//  Created by Codex on 7/3/26.
//

import Foundation
import Testing
@testable import OutPick

struct ChatProfileSyncManagerTests {
    @Test
    @MainActor
    func profileSnapshotMissDoesNotReadGRDBSynchronously() throws {
        let profileStore = try makeTemporaryStore()
        let manager = ChatProfileSyncManager(
            publicProfileRepository: UserPublicProfileRepositoryFake(),
            profileCache: profileStore
        )

        _ = try profileStore.upsertLocalChatUser(
            userID: "user-1",
            nickname: "Cached User",
            profileImagePath: "avatars/user-1.jpg"
        )

        #expect(manager.profile(for: "user-1") == nil)
    }

    @Test
    @MainActor
    func refreshProfilesUpdatesSnapshotAndReturnsChangedUserIDs() async throws {
        let profileStore = try makeTemporaryStore()
        let repository = UserPublicProfileRepositoryFake(profilesByID: [
            "user-1": UserPublicProfile(
                userID: "user-1",
                nickname: "Fresh User",
                avatarThumbPath: "avatars/fresh-user.jpg",
                avatarOriginalPath: nil,
                createdAt: nil,
                updatedAt: nil
            )
        ])
        let manager = ChatProfileSyncManager(
            publicProfileRepository: repository,
            profileCache: profileStore
        )

        let changedUserIDs = await manager.refreshProfiles(from: [
            makeMessage(senderUID: "user-1", senderNickname: "Old User")
        ])

        #expect(changedUserIDs == ["user-1"])
        let profile = manager.profile(for: "user-1")
        #expect(profile?.nickname == "Fresh User")
        #expect(profile?.profileImagePath == "avatars/fresh-user.jpg")
        #expect(try profileStore.fetchLocalChatUser(userID: "user-1")?.nickname == "Fresh User")
    }

    @Test
    @MainActor
    func resetClearsMainActorSnapshot() async throws {
        let profileStore = try makeTemporaryStore()
        let repository = UserPublicProfileRepositoryFake(profilesByID: [
            "user-1": UserPublicProfile(
                userID: "user-1",
                nickname: "Fresh User",
                avatarThumbPath: nil,
                avatarOriginalPath: nil,
                createdAt: nil,
                updatedAt: nil
            )
        ])
        let manager = ChatProfileSyncManager(
            publicProfileRepository: repository,
            profileCache: profileStore
        )

        _ = await manager.refreshProfiles(from: [
            makeMessage(senderUID: "user-1", senderNickname: "Old User")
        ])
        #expect(manager.profile(for: "user-1") != nil)

        manager.reset()

        #expect(manager.profile(for: "user-1") == nil)
    }

    private func makeTemporaryStore() throws -> GRDBChatProfileCacheStore {
        GRDBChatProfileCacheStore(database: try TemporaryAppDatabase.make())
    }

    private func makeMessage(
        senderUID: String,
        senderNickname: String,
        sentAt: Date = Date()
    ) -> ChatMessage {
        ChatMessage(
            ID: UUID().uuidString,
            seq: 0,
            roomID: "room-1",
            senderUID: senderUID,
            senderEmail: nil,
            senderNickname: senderNickname,
            senderAvatarPath: nil,
            messageType: .text,
            msg: "message",
            sentAt: sentAt,
            attachments: [],
            sharedContent: nil,
            replyPreview: nil,
            isFailed: false,
            isDeleted: false
        )
    }
}

private final class UserPublicProfileRepositoryFake: UserPublicProfileRepositoryProtocol {
    var profilesByID: [String: UserPublicProfile]

    init(profilesByID: [String: UserPublicProfile] = [:]) {
        self.profilesByID = profilesByID
    }

    func fetchProfile(userID: String) async throws -> UserPublicProfile {
        guard let profile = profilesByID[userID] else {
            throw FirebaseError.FailedToFetchProfile
        }
        return profile
    }

    func fetchProfiles(userIDs: [String]) async throws -> [String: UserPublicProfile] {
        profilesByID.filter { userIDs.contains($0.key) }
    }
}
