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
    let dbPool: DatabasePool
    
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
        
        migrator.registerMigration("createChatMessage") { db in
            try db.create(table: "chatMessage") { t in
                t.column("id", .text).primaryKey() // 메시지 UUID 등
                t.column("roomName", .text).notNull()
                t.column("senderID", .text).notNull()
                t.column("senderNickname", .text).notNull()
                t.column("msg", .text)
                t.column("sentAt", .datetime)
                t.column("attachments", .text) // JSON string
                t.column("isFailed", .boolean).notNull().defaults(to: false)
            }
        }
        
        migrator.registerMigration("createRoomParticipant") { db in
            try db.create(table: "roomParticipant") { t in
                t.column("roomId", .text).notNull()
                t.column("email", .text).notNull()
                t.primaryKey(["roomId", "email"]) // 복합 기본 키
            }
        }
        
        migrator.registerMigration("createRoomImage") { db in
            try db.create(table: "roomImage") { t in
                t.column("roomId", .text).notNull()
                t.column("imageName", .text).notNull()
                t.column("uploadedAt", .datetime).notNull()
                t.primaryKey(["roomId", "imageName"])
            }
        }
        
        try! migrator.migrate(dbPool)
    }
    
    // MARK: 사용자 프로필
    func insertUserProfile(_ profile: UserProfile) throws {
        try dbPool.write { db in
            try profile.save(db)
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
    
    // MARK: 메시지
    func saveChatMessage(_ message: ChatMessage) throws {
        let jsonData = try JSONEncoder().encode(message.attachments)
        let attachmentsJSON = String(data: jsonData, encoding: .utf8) ?? "[]"

        try dbPool.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO chatMessage
                (id, roomName, senderID, senderNickname, msg, sentAt, attachments, isFailed)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    UUID().uuidString,  // 또는 메시지 고유 ID
                    message.roomName,
                    message.senderID,
                    message.senderNickname,
                    message.msg,
                    message.sentAt,
                    attachmentsJSON,
                    message.isFailed
                ]
            )
        }
    }
    
    func fetchMessages(in roomName: String) throws -> [ChatMessage] {
        try dbPool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM chatMessage WHERE roomName = ? ORDER BY sentAt ASC",
                arguments: [roomName]
            )

            return try rows.compactMap { row in
                let attachmentsJSON = row["attachments"] as? String ?? "[]"
                let attachments = try JSONDecoder().decode([Attachment].self, from: Data(attachmentsJSON.utf8))

                return ChatMessage(
                    roomName: row["roomName"],
                    senderID: row["senderID"],
                    senderNickname: row["senderNickname"],
                    msg: row["msg"],
                    sentAt: row["sentAt"],
                    attachments: attachments,
                    isFailed: row["isFailed"] as? Bool ?? false
                )
            }
        }
    }
    
    func fetchLastMessageTimestamp(for roomID: String) throws -> Date? {
        try dbPool.read { db in
            let sql = """
            SELECT sentAt FROM chatMessage
            WHERE roomName = ?
            ORDER BY sentAt DESC
            LIMIT 1
            """
            return try Date.fetchOne(db, sql: sql, arguments: [roomID])
        }
    }
    
    func deleteMessages(inRoom roomID: String) throws {
        try dbPool.write { db in
            try db.execute(
                sql: "DELETE FROM chatMessage WHERE roomName = ?",
                arguments: [roomID]
            )
        }
    }
    
    // MARK: 중간 테이블 (방 - 이미지)
    func addImage(_ imageName: String, toRoom roomID: String, at uploadedAt: Date) throws {
        try dbPool.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO roomImage (roomId, imageName, uploadedAt) VALUES (?, ?, ?)",
                arguments: [roomID, imageName, uploadedAt]
            )
        }
    }

    func fetchImageNames(inRoom roomID: String) throws -> [String] {
        try dbPool.read { db in
            let sql = "SELECT imageName FROM roomImage WHERE roomId = ? ORDER BY uploadedAt"
            return try String.fetchAll(db, sql: sql, arguments: [roomID])
        }
    }
    
    func deleteImages(inRoom roomID: String) throws {
        try dbPool.write { db in
            try db.execute(
                sql: "DELETE FROM roomImage WHERE roomId = ?",
                arguments: [roomID]
            )
        }
    }
}
