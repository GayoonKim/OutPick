//
//  GRDBManagerMigrationTests.swift
//  OutPickTests
//
//  Created by Codex on 6/24/26.
//

import GRDB
import Testing
@testable import OutPick

struct GRDBManagerMigrationTests {
    @Test func baseUserMigrationBackfillsLocalUserFromLegacyProfileWithoutThumbPath() throws {
        let dbQueue = try DatabaseQueue()
        try dbQueue.write { db in
            try db.create(table: "userProfile") { t in
                t.column("email", .text).primaryKey()
                t.column("nickname", .text)
                t.column("profileImagePath", .text)
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

        let localUser = try dbQueue.read { db in
            try LocalUser.fetchOne(db, key: "legacy@example.com")
        }
        #expect(localUser?.nickname == "Legacy")
        #expect(localUser?.profileImagePath == "profiles/legacy.jpg")
    }

    @Test func baseUserMigrationPrefersThumbPathWhenLegacyProfileHasBothImageColumns() throws {
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
                    INSERT INTO userProfile (email, nickname, profileImagePath, thumbPath)
                    VALUES (?, ?, ?, ?)
                """,
                arguments: [
                    "thumb@example.com",
                    "Thumb",
                    "profiles/original.jpg",
                    "profiles/thumb.jpg"
                ]
            )
        }

        try migrateBaseUserSchema(dbQueue)

        let localUser = try dbQueue.read { db in
            try LocalUser.fetchOne(db, key: "thumb@example.com")
        }
        #expect(localUser?.nickname == "Thumb")
        #expect(localUser?.profileImagePath == "profiles/thumb.jpg")
    }

    private func migrateBaseUserSchema(_ dbQueue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        GRDBManager.registerBaseUserMigrations(&migrator)
        try migrator.migrate(dbQueue)
    }
}
