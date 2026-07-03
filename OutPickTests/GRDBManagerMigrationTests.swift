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
    @Test func baseUserMigrationCreatesCanonicalProfileDisplayCacheTables() throws {
        let dbQueue = try DatabaseQueue()

        try migrateBaseUserSchema(dbQueue)

        try dbQueue.read { db in
            #expect(try db.tableExists("LocalChatUser"))
            let roomMemberExists = try db.tableExists("RoomMember")
            #expect(roomMemberExists == false)

            let localUserColumns = try db.columns(in: "LocalChatUser").map(\.name)
            #expect(localUserColumns.contains("userID"))
            #expect(!localUserColumns.contains("email"))

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

    @Test func baseUserMigrationDoesNotCreateLegacyProfileOrMembershipTables() throws {
        let dbQueue = try DatabaseQueue()

        try migrateBaseUserSchema(dbQueue)

        try dbQueue.read { db in
            let userProfileExists = try db.tableExists("userProfile")
            let roomParticipantExists = try db.tableExists("roomParticipant")
            let roomMemberExists = try db.tableExists("RoomMember")
            let localUserExists = try db.tableExists("LocalUser")

            #expect(userProfileExists == false)
            #expect(roomParticipantExists == false)
            #expect(roomMemberExists == false)
            #expect(localUserExists == false)
        }
    }

    @Test func roomProfileDisplayCacheEvictsPerRoomByRecentMessageOrder() throws {
        let manager = try makeTemporaryManager()
        let baseDate = Date(timeIntervalSince1970: 1_000)

        for index in 0..<5 {
            _ = try manager.upsertLocalChatUser(
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

        _ = try manager.upsertLocalChatUser(userID: "current-user", nickname: "Me", profileImagePath: nil)
        _ = try manager.upsertLocalChatUser(userID: "leaving-room-user", nickname: "Leaving", profileImagePath: nil)
        _ = try manager.upsertLocalChatUser(userID: "other-room-user", nickname: "Other", profileImagePath: nil)

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

    @Test func rebuildChatMessageSenderUIDSchemaRemovesLegacySenderIDNotNullColumn() throws {
        let dbQueue = try DatabaseQueue()

        try dbQueue.write { db in
            try db.create(table: "chatMessage") { t in
                t.column("id", .text).primaryKey()
                t.column("seq", .integer).notNull().defaults(to: 0)
                t.column("roomID", .text).notNull()
                t.column("senderID", .text).notNull()
                t.column("senderUID", .text)
                t.column("senderEmail", .text)
                t.column("senderNickname", .text).notNull()
                t.column("msg", .text)
                t.column("sentAt", .datetime)
                t.column("attachments", .text)
                t.column("isFailed", .boolean).notNull().defaults(to: false)
                t.column("replyTo", .text)
            }
            try db.execute(
                sql: """
                INSERT INTO chatMessage
                (id, seq, roomID, senderID, senderUID, senderEmail, senderNickname, msg, attachments, isFailed)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    "message-1",
                    12,
                    "room-1",
                    "legacy-sender",
                    nil,
                    "legacy@example.com",
                    "Legacy",
                    "hello",
                    "[]",
                    false
                ]
            )

            try GRDBManager.rebuildChatMessageSenderUIDSchemaIfNeeded(in: db)
        }

        try dbQueue.read { db in
            let columns = try db.columns(in: "chatMessage").map(\.name)
            #expect(columns.contains("senderUID"))
            #expect(!columns.contains("senderID"))

            let row = try Row.fetchOne(db, sql: "SELECT senderUID, senderNickname, seq FROM chatMessage WHERE id = ?", arguments: ["message-1"])
            #expect(row?["senderUID"] as String? == "legacy-sender")
            #expect(row?["senderNickname"] as String? == "Legacy")
            #expect(row?["seq"] as Int64? == 12)
        }
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
