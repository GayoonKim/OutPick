//
//  ChatProfileSyncManagerTests.swift
//  OutPickTests
//
//  Created by Codex on 7/3/26.
//

import Foundation
import FirebaseFirestore
import GRDB
import Testing
@testable import OutPick

struct ChatProfileSyncManagerTests {
    @Test
    @MainActor
    func profileSnapshotMissDoesNotReadGRDBSynchronously() throws {
        let grdbManager = try makeTemporaryManager()
        let manager = ChatProfileSyncManager(
            userProfileRepository: UserProfileRepositoryFake(),
            grdbManager: grdbManager
        )

        _ = try grdbManager.upsertLocalChatUser(
            userID: "user-1",
            nickname: "Cached User",
            profileImagePath: "avatars/user-1.jpg"
        )

        #expect(manager.profile(for: "user-1") == nil)
    }

    @Test
    @MainActor
    func refreshProfilesUpdatesSnapshotAndReturnsChangedUserIDs() async throws {
        let grdbManager = try makeTemporaryManager()
        let repository = UserProfileRepositoryFake(profilesByID: [
            "user-1": UserProfile(
                email: "user-1@example.com",
                nickname: "Fresh User",
                thumbPath: "avatars/fresh-user.jpg"
            )
        ])
        let manager = ChatProfileSyncManager(
            userProfileRepository: repository,
            grdbManager: grdbManager
        )

        let changedUserIDs = await manager.refreshProfiles(from: [
            makeMessage(senderUID: "user-1", senderNickname: "Old User")
        ])

        #expect(changedUserIDs == ["user-1"])
        let profile = manager.profile(for: "user-1")
        #expect(profile?.nickname == "Fresh User")
        #expect(profile?.profileImagePath == "avatars/fresh-user.jpg")
        #expect(try grdbManager.fetchLocalChatUser(userID: "user-1")?.nickname == "Fresh User")
    }

    @Test
    @MainActor
    func resetClearsMainActorSnapshot() async throws {
        let grdbManager = try makeTemporaryManager()
        let repository = UserProfileRepositoryFake(profilesByID: [
            "user-1": UserProfile(email: "user-1@example.com", nickname: "Fresh User")
        ])
        let manager = ChatProfileSyncManager(
            userProfileRepository: repository,
            grdbManager: grdbManager
        )

        _ = await manager.refreshProfiles(from: [
            makeMessage(senderUID: "user-1", senderNickname: "Old User")
        ])
        #expect(manager.profile(for: "user-1") != nil)

        manager.reset()

        #expect(manager.profile(for: "user-1") == nil)
    }

    private func makeTemporaryManager() throws -> GRDBManager {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("OutPick.sqlite")
        let dbPool = try DatabasePool(path: databaseURL.path)
        return GRDBManager(dbPool: dbPool)
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

private final class UserProfileRepositoryFake: UserProfileRepositoryProtocol {
    var profilesByID: [String: UserProfile]

    init(profilesByID: [String: UserProfile] = [:]) {
        self.profilesByID = profilesByID
    }

    func resolveOrCreateUserDocumentID(authenticatedUser: AuthenticatedUser) async throws -> String {
        fatalError("Unused in ChatProfileSyncManagerTests")
    }

    func saveCurrentUserProfile(
        _ profile: UserProfile,
        userID: String,
        email: String,
        authenticatedUser: AuthenticatedUser?
    ) async throws {
        fatalError("Unused in ChatProfileSyncManagerTests")
    }

    func fetchCurrentUserProfile(userID: String, emailFallback: String) async throws -> UserProfile {
        fatalError("Unused in ChatProfileSyncManagerTests")
    }

    func fetchUserProfile(userID: String) async throws -> UserProfile {
        fatalError("Unused in ChatProfileSyncManagerTests")
    }

    func fetchUserProfiles(userIDs: [String]) async throws -> [String: UserProfile] {
        profilesByID.filter { userIDs.contains($0.key) }
    }

    func checkDuplicate(strToCompare: String, fieldToCompare: String, collectionName: String) async throws -> Bool {
        fatalError("Unused in ChatProfileSyncManagerTests")
    }

    func updateLastReadSeq(roomID: String, userUID: String, lastReadSeq: Int64) async throws {
        fatalError("Unused in ChatProfileSyncManagerTests")
    }

    func fetchLastReadSeq(for roomID: String, userUID: String) async throws -> Int64 {
        fatalError("Unused in ChatProfileSyncManagerTests")
    }

    func upsertDeviceID(userDocumentID: String, email: String, deviceID: String) async throws {
        fatalError("Unused in ChatProfileSyncManagerTests")
    }

    func listenToDeviceID(
        userDocumentID: String,
        onUpdate: @escaping (String?) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        NoopListenerRegistration()
    }

    func upsertPushDevice(userDocumentID: String, state: PushDeviceState) async throws {
        fatalError("Unused in ChatProfileSyncManagerTests")
    }
}

private final class NoopListenerRegistration: NSObject, ListenerRegistration {
    func remove() {}
}
