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
                t.column("roomID", .text).notNull()
                t.column("senderID", .text).notNull()
                t.column("senderNickname", .text).notNull()
                t.column("msg", .text)
                t.column("sentAt", .datetime)
                t.column("attachments", .text) // JSON string
                t.column("isFailed", .boolean).notNull().defaults(to: false)
                t.column("replyTo", .text)
            }
            
            try db.create(index: "idx_chatMessage_roomID_sentAt", on: "chatMessage", columns: ["roomID", "sentAt"], ifNotExists: true)
        }
        
        migrator.registerMigration(("createChatMessageFTS")) { db in
            try db.create(virtualTable: "chatMessageFTS", using: FTS5()) { t in
                t.column("msg")
                t.column("roomID")
                t.column("id").notIndexed()
            }
        }
        
        migrator.registerMigration("addReplyPreviewToChatMessage") { db in
            do {
                try db.alter(table: "chatMessage") { t in
                    t.add(column: "replyPreview", .text) // JSON string of ReplyPreview
                }
            } catch {
                // 컬럼이 이미 있으면 에러가 날 수 있으므로 무시(신규/기존 DB 모두 호환)
                print("[Migration] addReplyPreviewToChatMessage skipped or failed: \(error)")
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
    func saveChatMessage(_ message: ChatMessage) async throws {
        let jsonData = try JSONEncoder().encode(message.attachments)
        let attachmentsJSON = String(data: jsonData, encoding: .utf8) ?? "[]"
        
        let replyPreviewJSON: String? = {
            guard let rp = message.replyPreview else { return nil }
            do {
                let data = try JSONEncoder().encode(rp)
                return String(data: data, encoding: .utf8)
            } catch {
                print("replyPreview JSON 인코딩 실패: \(error)")
                return nil
            }
        }()
        
        try await dbPool.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO chatMessage
                (id, roomID, senderID, senderNickname, msg, sentAt, attachments, isFailed, replyPreview)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    message.ID,  // 또는 메시지 고유 ID
                    message.roomID,
                    message.senderID,
                    message.senderNickname,
                    message.msg,
                    message.sentAt,
                    attachmentsJSON,
                    message.isFailed,
                    replyPreviewJSON
                ]
            )
            
            do {
                try db.execute(
                    sql: "INSERT OR REPLACE INTO chatMessageFTS(id, msg, roomID) VALUES (?, ?, ?)",
                    arguments: [message.ID, message.msg, message.roomID]
                )
                
                print(#function, "✅✅✅✅✅✅✅✅✅✅ 메시지 저장 성공: ", message)
            } catch {
                print("FTS insert 실패: \(error)")
            }
        }
    }

    func fetchMessages(in roomID: String, containing keyword: String? = nil) async throws -> [ChatMessage] {
        try await dbPool.read { db in

            let rows: [Row]
            if let keyword = keyword, !keyword.isEmpty {

                let sql = """
                SELECT * FROM chatMessage
                WHERE roomID = ? AND msg LIKE ?
                ORDER BY sentAt ASC
                """
                
                let likeQuery = "%\(keyword)%"
                rows = try Row.fetchAll(db, sql: sql, arguments: [roomID, likeQuery])
            } else {
                let sql = "SELECT * FROM chatMessage WHERE roomID = ? ORDER BY sentAt ASC"
                rows = try Row.fetchAll(db, sql: sql, arguments: [roomID])
            }

            return try rows.compactMap { row in
                let attachmentsJSON = row["attachments"] as? String ?? "[]"
                let attachments = try JSONDecoder().decode([Attachment].self, from: Data(attachmentsJSON.utf8))
                
                let rpJSON = row["replyPreview"] as? String
                let replyPreview: ReplyPreview? = {
                    guard let rpJSON, let data = rpJSON.data(using: .utf8) else { return nil }
                    return try? JSONDecoder().decode(ReplyPreview.self, from: data)
                }()
                
                return ChatMessage(
                    ID: row["id"],
                    roomID: row["roomID"],
                    senderID: row["senderID"],
                    senderNickname: row["senderNickname"],
                    msg: row["msg"],
                    sentAt: row["sentAt"],
                    attachments: attachments,
                    replyPreview: replyPreview,
                    isFailed: (row["isFailed"] as? Int64 == 1)
                )
            }
        }
    }
    
    func fetchAllMessages(inRoom roomID: String) async throws -> [ChatMessage] {
        try await dbPool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM chatMessage WHERE roomID = ? ORDER BY sentAt ASC",
                arguments: [roomID]
            )

            return try rows.compactMap { row in
                let attachmentsJSON = row["attachments"] as? String ?? "[]"
                let attachments = try JSONDecoder().decode([Attachment].self, from: Data(attachmentsJSON.utf8))

                let rpJSON = row["replyPreview"] as? String
                let replyPreview: ReplyPreview? = {
                    guard let rpJSON, let data = rpJSON.data(using: .utf8) else { return nil }
                    return try? JSONDecoder().decode(ReplyPreview.self, from: data)
                }()

                return ChatMessage(
                    ID: row["id"],
                    roomID: row["roomID"],
                    senderID: row["senderID"],
                    senderNickname: row["senderNickname"],
                    msg: row["msg"],
                    sentAt: row["sentAt"],
                    attachments: attachments,
                    replyPreview: replyPreview,
                    isFailed: (row["isFailed"] as? Int64 == 1)
                )
            }
        }
    }

    // 디버깅용 함수 추가
//    func debugFTSContent() async throws {
//        try await dbPool.read { db in
//            print("�� === FTS 테이블 디버깅 ===")
//
//            // FTS 테이블 내용 확인
//            let ftsRows = try Row.fetchAll(db, sql: "SELECT * FROM chatMessageFTS LIMIT 5")
//            print("�� FTS 테이블 샘플 데이터:")
//            for (index, row) in ftsRows.enumerated() {
//                print("  \(index): id=\(row["id"] ?? "nil"), msg=\(row["msg"] ?? "nil"), roomID=\(row["roomID"] ?? "nil")")
//            }
//
//            // chatMessage 테이블과 비교
//            let chatRows = try Row.fetchAll(db, sql: "SELECT id, msg, roomID FROM chatMessage LIMIT 5")
//            print("�� chatMessage 테이블 샘플 데이터:")
//            for (index, row) in chatRows.enumerated() {
//                print("  \(index): id=\(row["id"] ?? "nil"), msg=\(row["msg"] ?? "nil"), roomID=\(row["roomID"] ?? "nil")")
//            }
//        }
//    }
    
    func fetchLastMessageTimestamp(for roomID: String) throws -> Date? {
        try dbPool.read { db in
            let sql = """
            SELECT sentAt FROM chatMessage
            WHERE roomID = ?
            ORDER BY sentAt DESC
            LIMIT 1
            """
            return try Date.fetchOne(db, sql: sql, arguments: [roomID])
        }
    }
    
    func fetchLastMessageID(for roomID: String) async throws -> String? {
        try await dbPool.read { db in
            let sql = """
            SELECT id FROM chatMessage
            WHERE roomID = ?
            ORDER BY sentAt DESC
            LIMIT 1
            """
            
            return try String.fetchOne(db, sql: sql, arguments: [roomID])
        }
    }
    
    func deleteMessages(inRoom roomID: String) throws {
        try dbPool.write { db in
            try db.execute(
                sql: "DELETE FROM chatMessage WHERE roomID = ?",
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
