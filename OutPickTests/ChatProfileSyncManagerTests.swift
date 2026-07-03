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
    @Test func profileCacheSupportsConcurrentReadWriteAndReset() throws {
        let grdbManager = try makeTemporaryManager()
        let manager = ChatProfileSyncManager(
            userProfileRepository: UserProfileRepositoryUnusedFake(),
            grdbManager: grdbManager
        )

        for index in 0..<20 {
            _ = try grdbManager.upsertLocalChatUser(
                userID: "user-\(index)",
                nickname: "User \(index)",
                profileImagePath: "avatars/user-\(index).jpg"
            )
        }

        DispatchQueue.concurrentPerform(iterations: 500) { iteration in
            let userID = "user-\(iteration % 20)"
            _ = manager.profile(for: userID)

            if iteration.isMultiple(of: 7) {
                manager.reset()
            }
        }

        let profile = manager.profile(for: "user-3")
        #expect(profile?.nickname == "User 3")
    }

    private func makeTemporaryManager() throws -> GRDBManager {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("OutPick.sqlite")
        let dbPool = try DatabasePool(path: databaseURL.path)
        return GRDBManager(dbPool: dbPool)
    }
}

private final class UserProfileRepositoryUnusedFake: UserProfileRepositoryProtocol {
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
        fatalError("Unused in ChatProfileSyncManagerTests")
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
