//
//  GRDBManager.swift
//  OutPick
//
//  Created by 김가윤 on 7/11/25.
//

import Foundation
import GRDB

final class GRDBManager {
    static let shared = GRDBManager()
    private let dbPool: DatabasePool
    
    private init() {
        // DB 파일 경로 설정
        let databaseURL = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("OutPick.sqlite")
        // DatabasePool 생성 (멀티스레드 대응)
        dbPool = try! DatabasePool(path: databaseURL.path)
        
        // 마이그레이션 수행
        var migrator = DatabaseMigrator()
        migrator.registerMigration("createUserProfile") { db in
            try db.create(table: "userProfile") { t in
                t.column("deviceID", .text)
                t.column("email", .text).primaryKey()
                t.column("gender", .text)
                t.column("birthdate", .text)
                t.column("nickname", .text)
                t.column("profileImagePath", .text)
                t.column("joinedRooms", .text) // JSON 인코딩된 [String]
                t.column("createdAt", .datetime).notNull()
            }
        }
        
        migrator.registerMigration("createRoomParticipant") { db in
            try db.create(table: "roomParticipant") { t in
                t.column("roomId", .text).notNull()
                t.column("email", .text).notNull()
                t.primaryKey(["roomId", "email"]) // 복합 기본 키
            }
        }
        
        try! migrator.migrate(dbPool)
    }
    
    // MARK: 사용자 프로필
    func insertUserProfile(_ profile: UserProfile) throws {
        try dbPool.write { db in
            try profile.insert(db)
        }
    }
    
    func fetchAllProfiles() throws -> [UserProfile] {
        try dbPool.read { db in
            try UserProfile.fetchAll(db)
        }
    }
    
    func fetchProfile(_ email: String) throws -> UserProfile? {
        try dbPool.read { db in
            try UserProfile.fetchOne(db, key: email)
        }
    }
    
    // MARK: 중간 테이블 관리 (방 - 사용자)
    func addUser(_ email: String, toRoom roomID: String) throws {
        try dbPool.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO roomParticipant (roomId, email) VALUES (?, ?)", arguments: [roomID, email])
        }
    }
    
    func removeUser(_ email: String, fromRoom roomID: String) throws {
        try dbPool.write { db in
            try db.execute(sql: "DELETE FROM roomParticipant WHERE roomId = ? AND email = ?", arguments: [roomID, email])
        }
    }
    
    func fetchUserProfiles(inRoom roomID: String) throws -> [UserProfile] {
        try dbPool.read { db in
            let sql = """
                            SELECT userProfile.*
                            FROM userProfile
                            JOIN roomParticipant ON userProfile.email = roomParticipant.email
                            WHERE roomParticipant.roomId = ?
                        """
            return try UserProfile.fetchAll(db, sql: sql, arguments: [roomID])
        }
    }
}
