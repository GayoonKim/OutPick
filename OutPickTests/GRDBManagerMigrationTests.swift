//
//  GRDBManagerMigrationTests.swift
//  OutPickTests
//
//  Created by Codex on 6/24/26.
//

import Foundation
import GRDB
import Testing
@testable import OutPick

struct GRDBManagerMigrationTests {
    @Test func baseUserMigrationCreatesCanonicalLocalChatUserTables() throws {
        let dbQueue = try DatabaseQueue()

        try migrateBaseUserSchema(dbQueue)

        try dbQueue.read { db in
            #expect(try db.tableExists("LocalChatUser"))
            #expect(try db.tableExists("RoomMember"))

            let localUserColumns = try db.columns(in: "LocalChatUser").map(\.name)
            #expect(localUserColumns.contains("userID"))
            #expect(!localUserColumns.contains("email"))

            let roomMemberColumns = try db.columns(in: "RoomMember").map(\.name)
            #expect(roomMemberColumns.contains("userID"))
            #expect(!roomMemberColumns.contains("userEmail"))

            #expect(try db.tableExists("RoomProfileDisplayCache"))
            let displayCacheColumns = try db.columns(in: "RoomProfileDisplayCache").map(\.name)
            #expect(displayCacheColumns.contains("roomID"))
            #expect(displayCacheColumns.contains("userID"))
            #expect(displayCacheColumns.contains("lastSeenAt"))
            #expect(displayCacheColumns.contains("lastMessageSeq"))
            #expect(displayCacheColumns.contains("lastMessageID"))
            #expect(displayCacheColumns.contains("updatedAt"))
        }
    }

    @Test func baseUserMigrationDoesNotBackfillLegacyUserProfile() throws {
        let dbQueue = try DatabaseQueue()
        try dbQueue.write { db in
            try db.create(table: "userProfile") { t in
                t.column("email", .text).primaryKey()
                t.column("nickname", .text)
                t.column("profileImagePath", .text)
                t.column("thumbPath", .text)
            }
            try db.execute(
                sql: """
                    INSERT INTO userProfile (email, nickname, profileImagePath)
                    VALUES (?, ?, ?)
                """,
                arguments: ["legacy@example.com", "Legacy", "profiles/legacy.jpg"]
            )
        }

        try migrateBaseUserSchema(dbQueue)

        let legacyTableExists = try dbQueue.read { db in
            #expect(!(try db.tableExists("userProfile")))
            return try db.tableExists("userProfile")
        }
        let localUser = try dbQueue.read { db in
            try LocalChatUser.fetchOne(db, key: "legacy@example.com")
        }
        #expect(legacyTableExists == false)
        #expect(localUser == nil)
    }

    @Test func roomProfileDisplayCacheEvictsPerRoomByRecentMessageOrder() throws {
        let manager = try makeTemporaryManager()
        let baseDate = Date(timeIntervalSince1970: 1_000)

        for index in 0..<5 {
            try manager.upsertLocalChatUser(
                userID: "user-\(index)",
                nickname: "User \(index)",
                profileImagePath: nil
            )
            try manager.upsertRoomProfileDisplayCache(
                roomID: "room-a",
                userID: "user-\(index)",
                lastSeenAt: baseDate.addingTimeInterval(TimeInterval(index)),
                lastMessageSeq: index,
                lastMessageID: "message-\(index)",
                updatedAt: baseDate,
                maxEntriesPerRoom: 3
            )
        }

        let cachedUserIDs = try manager.fetchRoomProfileDisplayCacheUserIDs(roomID: "room-a")

        #expect(cachedUserIDs == ["user-4", "user-3", "user-2"])
        #expect(try manager.countRoomProfileDisplayCache(roomID: "room-a") == 3)
    }

    @Test func localRoomCleanupDeletesDisplayCacheAndPrunesOrphanLocalChatUsers() throws {
        let manager = try makeTemporaryManager()
        let now = Date(timeIntervalSince1970: 2_000)

        try manager.upsertLocalChatUser(userID: "current-user", nickname: "Me", profileImagePath: nil)
        try manager.upsertLocalChatUser(userID: "leaving-room-user", nickname: "Leaving", profileImagePath: nil)
        try manager.upsertLocalChatUser(userID: "other-room-user", nickname: "Other", profileImagePath: nil)

        try manager.upsertRoomProfileDisplayCache(
            roomID: "leaving-room",
            userID: "leaving-room-user",
            lastSeenAt: now,
            lastMessageSeq: 1,
            lastMessageID: "leaving-message",
            updatedAt: now
        )
        try manager.upsertRoomProfileDisplayCache(
            roomID: "other-room",
            userID: "other-room-user",
            lastSeenAt: now,
            lastMessageSeq: 1,
            lastMessageID: "other-message",
            updatedAt: now
        )

        try manager.deleteLocalRoomDataAndPruneUsers(
            roomID: "leaving-room",
            currentUserID: "current-user"
        )

        #expect(try manager.countRoomProfileDisplayCache(roomID: "leaving-room") == 0)
        #expect(try manager.fetchLocalChatUser(userID: "leaving-room-user") == nil)
        #expect(try manager.fetchLocalChatUser(userID: "other-room-user") != nil)
        #expect(try manager.fetchLocalChatUser(userID: "current-user") != nil)
    }

    private func migrateBaseUserSchema(_ dbQueue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        GRDBManager.registerBaseUserMigrations(&migrator)
        try migrator.migrate(dbQueue)
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
