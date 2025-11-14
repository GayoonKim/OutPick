//
//  GRDBManager.swift
//  OutPick
//
//  Created by 김가윤 on 7/11/25.
//

import Foundation

import GRDB

// MARK: - Minimal GRDB models used by GRDBManager

/// LocalUser(email PK, nickname, profileImagePath)
struct LocalUser: Codable, FetchableRecord, PersistableRecord, Hashable {
    static let databaseTableName = "LocalUser"
    enum Columns: String, ColumnExpression { case email, nickname, profileImagePath }

    let email: String        // PK
    var nickname: String
    var profileImagePath: String?

    // Upsert-friendly
    static let persistenceConflictPolicy = PersistenceConflictPolicy(insert: .replace, update: .replace)
}

/// RoomMember(roomID, userEmail)
struct RoomMember: Codable, FetchableRecord, PersistableRecord, Hashable {
    static let databaseTableName = "RoomMember"
    enum Columns: String, ColumnExpression { case roomID, userEmail }

    let roomID: String
    let userEmail: String    // FK → LocalUser.email
}

struct ImageIndexMeta: FetchableRecord, Decodable {
    let roomID: String
    let messageID: String
    let idx: Int
    let thumbKey: String?
    let originalKey: String?
    let thumbURL: String?
    let originalURL: String?
    let width: Int?
    let height: Int?
    let bytesOriginal: Int?
    let hash: String?
    let isFailed: Bool
    let localThumb: String?
    let sentAt: Date
}

struct VideoIndexMeta: FetchableRecord, Decodable {
    let roomID: String
    let messageID: String
    let idx: Int
    let thumbKey: String?
    let originalKey: String?
    let thumbURL: String?
    let originalURL: String?
    let width: Int?
    let height: Int?
    let bytesOriginal: Int?
    let duration: Double?
    let approxBitrateMbps: Double?
    let preset: String?
    let hash: String?
    let isFailed: Bool
    let localThumb: String?
    let sentAt: Date
}

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
        migrator.registerMigration("foreignKeysOn") { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON;")
        }
        // Minimal LocalUser table (email, nickname, profileImagePath)
        migrator.registerMigration("createLocalUser_min") { db in
            try db.create(table: "LocalUser", options: [.ifNotExists]) { t in
                t.column("email", .text).primaryKey()          // PK(email)
                t.column("nickname", .text).notNull()
                t.column("profileImagePath", .text)
            }
            try db.create(index: "idx_LocalUser_nickname", on: "LocalUser", columns: ["nickname"], ifNotExists: true)
        }
        
        // RoomMember junction table (roomID, userEmail)
        migrator.registerMigration("createRoomMember_min") { db in
            try db.create(table: "RoomMember", options: [.ifNotExists]) { t in
                t.column("roomID", .text).notNull()
                t.column("userEmail", .text).notNull().indexed().references("LocalUser", column: "email", onDelete: .cascade)
                t.primaryKey(["roomID", "userEmail"]) // composite PK
            }
            try db.create(index: "idx_RoomMember_room", on: "RoomMember", columns: ["roomID"], ifNotExists: true)
        }
        
        // Backfill LocalUser from legacy userProfile (if exists)
        migrator.registerMigration("backfill_LocalUser_from_userProfile") { db in
            if try db.tableExists("userProfile") {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO LocalUser (email, nickname, profileImagePath)
                    SELECT email, COALESCE(nickname, ''), COALESCE(thumbPath, profileImagePath)
                      FROM userProfile
                """)
            }
        }
        
        // Backfill RoomMember from legacy roomParticipant (if exists)
        migrator.registerMigration("migrate_roomParticipant_to_RoomMember") { db in
            if try db.tableExists("roomParticipant") {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO RoomMember (roomID, userEmail)
                    SELECT roomId, email FROM roomParticipant
                """)
            }
        }
        migrator.registerMigration("createUserProfile") { db in
            try db.create(table: "userProfile") { t in
                t.column("deviceID", .text)
                t.column("email", .text).primaryKey()
                t.column("gender", .text)
                t.column("birthdate", .text)
                t.column("nickname", .text)
                t.column("profileImagePath", .text)
                t.column("thumbPath", .text)
                t.column("originalPath", .text)
                t.column("joinedRooms", .text) // JSON 인코딩된 [String]
                t.column("createdAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("addThumbAndOriginalToUserProfile") { db in
            do {
                try db.alter(table: "userProfile") { t in
                    t.add(column: "thumbPath", .text)
                    t.add(column: "originalPath", .text)
                }
            } catch {
                // 컬럼이 이미 존재하면 에러가 날 수 있으므로 무시(신규/기존 DB 모두 호환)
                print("[Migration] addThumbAndOriginalToUserProfile skipped or failed: \(error)")
            }
            // 기존 profileImagePath 값을 thumbPath로 백필(있을 때만)
            do {
                try db.execute(sql: """
                    UPDATE userProfile
                       SET thumbPath = COALESCE(thumbPath, profileImagePath)
                     WHERE (thumbPath IS NULL OR thumbPath = '')
                       AND (profileImagePath IS NOT NULL AND profileImagePath <> '')
                """)
            } catch {
                print("[Migration] backfill thumbPath from profileImagePath failed: \(error)")
            }
        }

        migrator.registerMigration("createChatMessage") { db in
            try db.create(table: "chatMessage") { t in
                t.column("id", .text).primaryKey() // 메시지 UUID 등
                t.column("seq", .integer).notNull().defaults(to: 0)  // 방 내 단조 증가 시퀀스
                t.column("roomID", .text).notNull()
                t.column("senderID", .text).notNull()
                t.column("senderNickname", .text).notNull()
                t.column("senderAvatarPath", .text)
                t.column("msg", .text)
                t.column("sentAt", .datetime)
                t.column("attachments", .text) // JSON string
                t.column("isFailed", .boolean).notNull().defaults(to: false)
                t.column("replyTo", .text)
            }
            
            try db.create(index: "idx_chatMessage_roomID_sentAt", on: "chatMessage", columns: ["roomID", "sentAt"], ifNotExists: true)
            try db.create(index: "idx_chatMessage_roomID_seq", on: "chatMessage", columns: ["roomID", "seq"], ifNotExists: true)
        }
        
        migrator.registerMigration("addSeqToChatMessage") { db in
            do {
                try db.alter(table: "chatMessage") { t in
                    t.add(column: "seq", .integer).notNull().defaults(to: 0)
                }
            } catch {
                print("[Migration] addSeqToChatMessage (add column) skipped or failed: \(error)")
            }
            do {
                try db.create(index: "idx_chatMessage_roomID_seq",
                              on: "chatMessage",
                              columns: ["roomID", "seq"],
                              ifNotExists: true)
            } catch {
                print("[Migration] addSeqToChatMessage (create index) skipped or failed: \(error)")
            }
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
        
        migrator.registerMigration("addIsDeletedToChatMessage") { db in
            do {
                try db.alter(table: "chatMessage") { t in
                    t.add(column: "isDeleted", .boolean).notNull().defaults(to: false)
                }
            } catch {
                print("[Migration] addIsDeletedToChatMessage skipped or failed: \(error)")
            }
        }

        migrator.registerMigration("addSenderAvatarPathToChatMessage") { db in
            do {
                try db.alter(table: "chatMessage") { t in
                    t.add(column: "senderAvatarPath", .text)
                }
            } catch {
                // 컬럼이 이미 존재하면 에러가 날 수 있으므로 무시(신규/기존 DB 모두 호환)
                print("[Migration] addSenderAvatarPathToChatMessage skipped or failed: \(error)")
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
        
        migrator.registerMigration("createImageIndex") { db in
            try db.create(table: "imageIndex") { t in
                t.column("roomID", .text).notNull()
                t.column("messageID", .text).notNull()
                t.column("idx", .integer).notNull()
                t.column("thumbKey", .text)
                t.column("originalKey", .text)
                t.column("thumbURL", .text)
                t.column("originalURL", .text)
                t.column("width", .integer)
                t.column("height", .integer)
                t.column("bytesOriginal", .integer)
                t.column("hash", .text)
                t.column("isFailed", .boolean).notNull().defaults(to: false)
                t.column("localThumb", .text)
                t.column("sentAt", .datetime).notNull()
                t.primaryKey(["roomID", "messageID", "idx"]) // 유니크 키
            }
            try db.create(index: "idx_imageIndex_room_sentAt", on: "imageIndex", columns: ["roomID", "sentAt"], ifNotExists: true)
            try db.create(index: "idx_imageIndex_messageID", on: "imageIndex", columns: ["messageID"], ifNotExists: true)
        }
        
        migrator.registerMigration("createVideoIndex") { db in
            try db.create(table: "videoIndex") { t in
                t.column("roomID", .text).notNull()
                t.column("messageID", .text).notNull()
                t.column("idx", .integer).notNull()
                
                // 이미지 인덱스와 컬럼 구성 맞춤(키/URL 모두 보관)
                t.column("thumbKey", .text)
                t.column("originalKey", .text)
                t.column("thumbURL", .text)
                t.column("originalURL", .text)
                
                t.column("width", .integer)
                t.column("height", .integer)
                t.column("bytesOriginal", .integer)
                
                // 동영상 전용(옵션)
                t.column("duration", .double)
                t.column("approxBitrateMbps", .double)
                t.column("preset", .text)
                
                t.column("hash", .text)
                t.column("isFailed", .boolean).notNull().defaults(to: false)
                t.column("localThumb", .text)
                t.column("sentAt", .datetime).notNull()
                
                t.primaryKey(["roomID", "messageID", "idx"])
            }
            try db.create(index: "idx_videoIndex_room_sentAt",
                          on: "videoIndex",
                          columns: ["roomID", "sentAt"],
                          ifNotExists: true)
            try db.create(index: "idx_videoIndex_messageID",
                          on: "videoIndex",
                          columns: ["messageID"],
                          ifNotExists: true)
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
                 ORDER BY userProfile.nickname COLLATE NOCASE ASC
            """
            return try UserProfile.fetchAll(db, sql: sql, arguments: [roomID])
        }
    }
    
    // MARK: 방
//    func fetchRoomInfo(roomID: String) throws -> ChatRoom? {
//        try dbPool.read { db -> ChatRoom? in
//            // rooms 테이블에서 방 기본 정보 조회
//            struct RoomRow: FetchableRecord, Decodable {
//                var ID: String
//                var roomName: String
//                var roomDescription: String
//                var creatorID: String
//                var createdAt: Date
//                var thumbPath: String?
//                var originalPath: String?
//                var lastMessageAt: Date?
//                var lastMessage: String?
//            }
//            
//            guard let row = try RoomRow.fetchOne(
//                db,
//                sql: """
//                SELECT id AS ID,
//                       roomName,
//                       roomDescription,
//                       creatorID,
//                       createdAt,
//                       thumbPath,
//                       originalPath,
//                       lastMessageAt,
//                       lastMessage
//                FROM rooms
//                WHERE id = ?
//                """,
//                arguments: [roomID]
//            ) else {
//                return nil
//            }
//            
//            // 참여자 IDs 조회 (신규 RoomMember 우선, 레거시 roomParticipant 폴백)
//            let participants: [String] = try {
//                if try db.tableExists("RoomMember") {
//                    return try String.fetchAll(
//                        db,
//                        sql: "SELECT userEmail FROM RoomMember WHERE roomID = ?",
//                        arguments: [roomID]
//                    )
//                } else {
//                    return try String.fetchAll(
//                        db,
//                        sql: "SELECT email FROM roomParticipant WHERE roomId = ?",
//                        arguments: [roomID]
//                    )
//                }
//            }()
//            
//            return ChatRoom(
//                ID: row.ID,
//                roomName: row.roomName,
//                roomDescription: row.roomDescription,
//                participants: participants,
//                creatorID: row.creatorID,
//                createdAt: row.createdAt,
//                thumbPath: row.thumbPath,
//                originalPath: row.originalPath,
//                lastMessageAt: row.lastMessageAt,
//                lastMessage: row.lastMessage,
//                activeAnnouncementID: nil,
//                activeAnnouncement: nil,
//                announcementUpdatedAt: nil
//            )
//        }
//    }
    
    // MARK: 메시지
    /// 여러 메시지를 한 번에 저장하고, 마지막에만 조건부 pruneMessages 실행
    func saveChatMessages(_ messages: [ChatMessage]) async throws {
        guard !messages.isEmpty else { return }
        
        // Write messages + image index (same transaction per write block)
        try await dbPool.write { db in
            for message in messages {
                // 1) Validate required fields (skip invalid rows to honor NOT NULL constraints)
                guard !message.roomID.isEmpty,
                      !message.senderID.isEmpty,
                      !message.senderNickname.isEmpty else {
#if DEBUG
                    print("[GRDB] skip invalid message: id=\(message.ID) roomID/sender fields missing")
#endif
                    continue
                }
                
                // 2) Attachments sort + JSON encode
                let attachmentsJSON: String = {
                    do {
                        let sorted = message.attachments.sorted { $0.index < $1.index }
                        let data = try JSONEncoder().encode(sorted)
                        return String(data: data, encoding: .utf8) ?? "[]"
                    } catch {
                        print("attachments JSON 인코딩 실패: \(error)")
                        return "[]"
                    }
                }()
                
                // 3) JSON encode replyPreview
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

                // 4) Upsert chatMessage row
                try db.execute(
                    sql: """
                    INSERT OR REPLACE INTO chatMessage
                    (id, seq, roomID, senderID, senderNickname, senderAvatarPath, msg, sentAt, attachments, isFailed, replyPreview, isDeleted)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        message.ID,
                        message.seq,
                        message.roomID,
                        message.senderID,
                        message.senderNickname,
                        message.senderAvatarPath,
                        message.msg,
                        message.sentAt,
                        attachmentsJSON,
                        message.isFailed,
                        replyPreviewJSON,
                        message.isDeleted
                    ]
                )
#if DEBUG
                print("[GRDB] saveChatMessages: upsert message id=\(message.ID) room=\(message.roomID)")
#endif
                
                // 5) FTS index: ensure non-nil text (image-only messages may have nil msg)
                let ftsMsg: String = message.msg ?? ""
                do {
                    try db.execute(
                        sql: "INSERT OR REPLACE INTO chatMessageFTS(id, msg, roomID) VALUES (?, ?, ?)",
                        arguments: [message.ID, ftsMsg, message.roomID]
                    )
                } catch {
                    print("FTS insert 실패: \(error)")
                }
                
                // 6) Image index upsert for this message (meta only)
                try self.upsertImageIndex(for: message, in: db)
                
                // 6b) Video index upsert for this message (meta only)
                try self.upsertVideoIndex(for: message, in: db)
            }
        }
        
        // 7) Conditional prune outside of write block to avoid nested writes
        if let lastMessage = messages.last {
            let roomID = lastMessage.roomID
            let count = try self.countMessages(inRoom: roomID)
            if count > 3300 {
                try self.pruneMessages(inRoom: roomID, keepLast: 3000)
            }
        }
        
#if DEBUG
        let summary = messages.map { "\($0.ID)@\($0.roomID)" }.joined(separator: ", ")
        print("saveChatMessages completed [\(messages.count)]: \(summary)")
#endif
    }
    
    /// 방의 메시지 개수를 반환하는 헬퍼 함수
    func countMessages(inRoom roomID: String) throws -> Int {
        try dbPool.read { db in
            return try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM chatMessage WHERE roomID = ?",
                arguments: [roomID]
            ) ?? 0
        }
    }
    
    // 특정 메시지들의 isDeleted 상태를 업데이트
    func updateMessagesIsDeleted(_ ids: [String], isDeleted: Bool, inRoom roomID: String) async throws {
        guard !ids.isEmpty else { return }
        try await dbPool.write { db in
            let placeholders = ids.map { _ in "?" }.joined(separator: ",")
            let sql = "UPDATE chatMessage SET isDeleted = ? WHERE roomID = ? AND id IN (\(placeholders))"
            var args: [DatabaseValueConvertible] = [isDeleted, roomID]
            args.append(contentsOf: ids)
            try db.execute(sql: sql, arguments: StatementArguments(args))
        }
    }
    
    // replyPreview.messageID 가 특정 IDs에 해당하는 레코드들의 preview.isDeleted 를 일괄 업데이트 (JSON1 사용)
    func updateReplyPreviewsIsDeleted(referencing ids: [String], isDeleted: Bool, inRoom roomID: String) async throws {
        guard !ids.isEmpty else { return }
        try await dbPool.write { db in
            let placeholders = ids.map { _ in "?" }.joined(separator: ",")
            // JSON1: replyPreview -> json_set(..., '$.isDeleted', ?) and filter by json_extract(..., '$.messageID') IN (...)
            let sql = """
            UPDATE chatMessage
               SET replyPreview = json_set(replyPreview, '$.isDeleted', ?)
             WHERE roomID = ?
               AND replyPreview IS NOT NULL
               AND json_extract(replyPreview, '$.messageID') IN (\(placeholders))
            """
            var args: [DatabaseValueConvertible] = [isDeleted ? 1 : 0, roomID]
            args.append(contentsOf: ids)
            try db.execute(sql: sql, arguments: StatementArguments(args))
        }
    }
    
    /// 최근 메시지 N개를 로컬 DB에서 조회 (시간 오름차순으로 반환)
    ///  ORDER BY sentAt DESC, id DESC
    func fetchRecentMessages(inRoom roomID: String, limit: Int) async throws -> [ChatMessage] {
        try await dbPool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM chatMessage
                WHERE roomID = ?
                ORDER BY seq DESC, id DESC
                LIMIT ?
                """,
                arguments: [roomID, limit]
            )
            
            // UI는 보통 오래된 → 최신 순(ASC)을 기대하므로 역순으로 변환
            let ascRows = rows.reversed()
            
            return try ascRows.compactMap { row in
                let attachmentsJSON = row["attachments"] as? String ?? "[]"
                let attachments = try JSONDecoder().decode([Attachment].self, from: Data(attachmentsJSON.utf8))
                
                let rpJSON = row["replyPreview"] as? String
                let replyPreview: ReplyPreview? = {
                    guard let rpJSON, let data = rpJSON.data(using: .utf8) else { return nil }
                    return try? JSONDecoder().decode(ReplyPreview.self, from: data)
                }()
                
                var message = ChatMessage(
                    ID: row["id"],
                    seq: (row["seq"] as? Int64) ?? 0,
                    roomID: row["roomID"],
                    senderID: row["senderID"],
                    senderNickname: row["senderNickname"],
                    msg: row["msg"],
                    sentAt: row["sentAt"],
                    attachments: attachments,
                    replyPreview: replyPreview,
                    isFailed: (row["isFailed"] as? Int64 == 1)
                )
                message.isDeleted = (row["isDeleted"] as? Int64 == 1)
                if let avatar = row["senderAvatarPath"] as? String {
                    message.senderAvatarPath = avatar
                }
                return message
            }
        }
    }
    // SELECT id, sentAt FROM chatMessage WHERE roomID = ? AND id = ? LIMIT 1
    func fetchOlderMessages(inRoom roomID: String, before anchorMessageID: String, limit: Int) async throws -> [ChatMessage] {
        try await dbPool.read { db in
            // 앵커 메시지의 sentAt을 조회
            guard let anchorRow = try Row.fetchOne(
                db,
                sql: "SELECT id, seq FROM chatMessage WHERE roomID = ? AND id = ? LIMIT 1",
                arguments: [roomID, anchorMessageID]
            ) else {
                return []
            }
            let anchorSeq: Int64 = (anchorRow["seq"] as? Int64) ?? 0
            
            // 앵커보다 과거인 메시지를 최신순으로 먼저 가져온 뒤, 반환 시 ASC로 뒤집기
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM chatMessage
                WHERE roomID = ?
                AND seq < ?
                ORDER BY seq DESC, id DESC
                LIMIT ?
                """,
                arguments: [roomID, anchorSeq, limit]
            )
            
            let ascRows = rows.reversed()
            
            return try ascRows.compactMap { row in
                let attachmentsJSON = row["attachments"] as? String ?? "[]"
                let attachments = try JSONDecoder().decode([Attachment].self, from: Data(attachmentsJSON.utf8))
                
                let rpJSON = row["replyPreview"] as? String
                let replyPreview: ReplyPreview? = {
                    guard let rpJSON, let data = rpJSON.data(using: .utf8) else { return nil }
                    return try? JSONDecoder().decode(ReplyPreview.self, from: data)
                }()
                
                var message = ChatMessage(
                    ID: row["id"], seq: (row["seq"] as? Int64) ?? 0,
                    roomID: row["roomID"],
                    senderID: row["senderID"],
                    senderNickname: row["senderNickname"],
                    msg: row["msg"],
                    sentAt: row["sentAt"],
                    attachments: attachments,
                    replyPreview: replyPreview,
                    isFailed: (row["isFailed"] as? Int64 == 1)
                )
                message.isDeleted = (row["isDeleted"] as? Int64 == 1)
                if let avatar = row["senderAvatarPath"] as? String {
                    message.senderAvatarPath = avatar
                }
                return message
            }
        }
    }
    
    /// 오래된 메시지를 삭제하여 최근 N개만 유지 (batchSize 지원)
    /// ORDER BY sentAt ASC
    func pruneMessages(inRoom roomID: String, keepLast count: Int, batchSize: Int = 500) throws {
        try dbPool.write { db in
            // 현재 메시지 개수 확인
            let totalCount = try self.countMessages(inRoom: roomID)
            
            if totalCount > count {
                let toDelete = min(totalCount - count, batchSize)
                // 먼저 삭제 대상 메시지 ID 목록을 수집
                let idRows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT id FROM chatMessage
                    WHERE roomID = ?
                    ORDER BY seq ASC, id ASC
                    LIMIT ?
                    """,
                    arguments: [roomID, toDelete]
                )
                let ids: [String] = idRows.compactMap { $0["id"] }
                guard !ids.isEmpty else { return }
                
                let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
                
                // 1) imageIndex 청소
                try db.execute(sql: "DELETE FROM imageIndex WHERE roomID = ? AND messageID IN (\(placeholders))",
                               arguments: StatementArguments([roomID] + ids))
                // 1b) videoIndex 청소
                try db.execute(sql: "DELETE FROM videoIndex WHERE roomID = ? AND messageID IN (\(placeholders))",
                               arguments: StatementArguments([roomID] + ids))
                // 2) FTS 청소
                try db.execute(sql: "DELETE FROM chatMessageFTS WHERE id IN (\(placeholders))",
                               arguments: StatementArguments(ids))
                // 3) chatMessage 삭제
                try db.execute(
                    sql: "DELETE FROM chatMessage WHERE id IN (\(placeholders))",
                    arguments: StatementArguments(ids)
                )
                
                let afterCount = try self.countMessages(inRoom: roomID)
                print("[GRDBManager] Pruned \(ids.count) old messages in room \(roomID). Total after prune: \(afterCount)")
            }
        }
    }
    
    // ORDER BY sentAt ASC
    func fetchMessages(in roomID: String, containing keyword: String? = nil) async throws -> [ChatMessage] {
        try await dbPool.read { db in
            
            let rows: [Row]
            if let keyword = keyword, !keyword.isEmpty {
                
                let sql = """
                SELECT * FROM chatMessage
                WHERE roomID = ? AND msg LIKE ?
                ORDER BY seq ASC, id ASC
                """
                
                let likeQuery = "%\(keyword)%"
                rows = try Row.fetchAll(db, sql: sql, arguments: [roomID, likeQuery])
            } else {
                let sql = "SELECT * FROM chatMessage WHERE roomID = ? ORDER BY seq ASC, id ASC"
                // SELECT * FROM chatMessage WHERE roomID = ? ORDER BY sentAt ASC
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
                
                var message = ChatMessage(
                    ID: row["id"],
                    seq: (row["seq"] as? Int64) ?? 0,
                    roomID: row["roomID"],
                    senderID: row["senderID"],
                    senderNickname: row["senderNickname"],
                    msg: row["msg"],
                    sentAt: row["sentAt"],
                    attachments: attachments,
                    replyPreview: replyPreview,
                    isFailed: (row["isFailed"] as? Int64 == 1)
                )
                message.isDeleted = (row["isDeleted"] as? Int64 == 1)
                if let avatar = row["senderAvatarPath"] as? String {
                    message.senderAvatarPath = avatar
                }
                return message
            }
        }
    }
    
    // ORDER BY sentAt ASC
    func fetchAllMessages(inRoom roomID: String) async throws -> [ChatMessage] {
        try await dbPool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM chatMessage WHERE roomID = ? ORDER BY seq ASC, id ASC",
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
                
                var message = ChatMessage(
                    ID: row["id"],
                    seq: (row["seq"] as? Int64) ?? 0,
                    roomID: row["roomID"],
                    senderID: row["senderID"],
                    senderNickname: row["senderNickname"],
                    msg: row["msg"],
                    sentAt: row["sentAt"],
                    attachments: attachments,
                    replyPreview: replyPreview,
                    isFailed: (row["isFailed"] as? Int64 == 1)
                )
                message.isDeleted = (row["isDeleted"] as? Int64 == 1)
                if let avatar = row["senderAvatarPath"] as? String {
                    message.senderAvatarPath = avatar
                }
                return message
            }
        }
    }
    
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
            try db.execute(sql: "DELETE FROM chatMessage WHERE roomID = ?", arguments: [roomID])
            try db.execute(sql: "DELETE FROM imageIndex WHERE roomID = ?", arguments: [roomID])
            try db.execute(sql: "DELETE FROM chatMessageFTS WHERE roomID = ?", arguments: [roomID])
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
    
    // MARK: - Image Index Upsert
    private func upsertImageIndex(for message: ChatMessage, in db: Database) throws {
        // Clean existing rows for this message (idempotent upsert)
        try db.execute(
            sql: "DELETE FROM imageIndex WHERE roomID = ? AND messageID = ?",
            arguments: [message.roomID, message.ID]
        )
        
        let atts = message.attachments
            .filter { $0.type == .image }
            .sorted { $0.index < $1.index }
        
        guard !atts.isEmpty else { return }
        
        let when = message.sentAt ?? Date()
        for att in atts {
            try db.execute(sql: """
            INSERT OR REPLACE INTO imageIndex
            (roomID, messageID, idx, thumbKey, originalKey, thumbURL, originalURL, width, height, bytesOriginal, hash, isFailed, localThumb, sentAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
                           arguments: [
                            message.roomID,
                            message.ID,
                            att.index,
                            // 캐시 키는 해시를 우선 사용(없으면 nil)
                            att.hash.isEmpty ? nil : att.hash,
                            att.hash.isEmpty ? nil : (att.hash + ":orig"),
                            att.pathThumb.isEmpty ? nil : att.pathThumb,
                            att.pathOriginal.isEmpty ? nil : att.pathOriginal,
                            att.width,
                            att.height,
                            att.bytesOriginal,
                            att.hash.isEmpty ? nil : att.hash,
                            message.isFailed,
                            message.isFailed ? (att.pathThumb.isEmpty ? nil : att.pathThumb) : nil,
                            when
                           ])
        }
    }
    
    func fetchImageIndex(inRoom roomID: String, forMessageIDs ids: [String]) async throws -> [ImageIndexMeta] {
        guard !ids.isEmpty else { return [] }
        return try await dbPool.read { db in
            let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
            let sql = """
            SELECT roomID, messageID, idx, thumbKey, originalKey, thumbURL, originalURL,
                   width, height, bytesOriginal, hash, isFailed, localThumb, sentAt
              FROM imageIndex
             WHERE roomID = ?
               AND messageID IN (\(placeholders))
             ORDER BY sentAt ASC, messageID ASC, idx ASC
            """
            var args: [DatabaseValueConvertible] = [roomID]
            args.append(contentsOf: ids)
            return try ImageIndexMeta.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }
    }

    /// 방의 이미지 인덱스 총 개수
    func countImageIndex(inRoom roomID: String) throws -> Int {
        try dbPool.read { db in
            try Int.fetchOne(db,
                             sql: "SELECT COUNT(*) FROM imageIndex WHERE roomID = ?",
                             arguments: [roomID]) ?? 0
        }
    }

    /// 최신순으로 방의 이미지 인덱스 페이지 조회 (DESC)
    /// - Parameters:
    ///   - roomID: 대상 방 ID
    ///   - limit: 최대 개수
    /// - Returns: 최신순(DESC)으로 정렬된 ImageIndexMeta 배열
    func fetchLatestImageIndex(inRoom roomID: String, limit: Int) throws -> [ImageIndexMeta] {
        try dbPool.read { db in
            try ImageIndexMeta.fetchAll(
                db,
                sql: """
                    SELECT roomID, messageID, idx, thumbKey, originalKey, thumbURL, originalURL,
                           width, height, bytesOriginal, hash, isFailed, localThumb, sentAt
                      FROM imageIndex
                     WHERE roomID = ?
                     ORDER BY sentAt DESC, messageID DESC, idx ASC
                     LIMIT ?
                """,
                arguments: [roomID, limit]
            )
        }
    }

    /// 앵커 이전(과거) 이미지 인덱스 페이지 조회 (DESC 키셋 페이지네이션)
    /// - Parameters:
    ///   - roomID: 방 ID
    ///   - beforeSentAt: 이 시각 이전의 레코드만
    ///   - beforeMessageID: 동시각 동률일 때 messageID로 타이브레이커
    ///   - limit: 최대 개수
    func fetchOlderImageIndex(inRoom roomID: String,
                              beforeSentAt: Date,
                              beforeMessageID: String,
                              limit: Int) throws -> [ImageIndexMeta] {
        try dbPool.read { db in
            try ImageIndexMeta.fetchAll(
                db,
                sql: """
                    SELECT roomID, messageID, idx, thumbKey, originalKey, thumbURL, originalURL,
                           width, height, bytesOriginal, hash, isFailed, localThumb, sentAt
                      FROM imageIndex
                     WHERE roomID = ?
                       AND (sentAt < ? OR (sentAt = ? AND messageID < ?))
                     ORDER BY sentAt DESC, messageID DESC, idx ASC
                     LIMIT ?
                """,
                arguments: [roomID, beforeSentAt, beforeSentAt, beforeMessageID, limit]
            )
        }
    }
    
    
    //MARK: ImageIndex 삭제 관련 함수
    func deleteImageIndex(forMessageID messageID: String, inRoom roomID: String? = nil) throws {
        try dbPool.write { db in
            if let roomID {
                try db.execute(
                    sql: "DELETE FROM imageIndex WHERE roomID = ? AND messageID = ?",
                    arguments: [roomID, messageID]
                )
            } else {
                try db.execute(
                    sql: "DELETE FROM imageIndex WHERE messageID = ?",
                    arguments: [messageID]
                )
            }
        }
    }
    
    /// Batch deletion variant for multiple messageIDs.
    /// If `roomID` is provided, the deletion is scoped to that room; otherwise it deletes across all rooms.
    func deleteImageIndex(forMessageIDs messageIDs: [String], inRoom roomID: String? = nil) throws {
        guard !messageIDs.isEmpty else { return }
        let placeholders = Array(repeating: "?", count: messageIDs.count).joined(separator: ",")
        try dbPool.write { db in
            if let roomID {
                var args: [DatabaseValueConvertible] = [roomID]
                args.append(contentsOf: messageIDs)
                try db.execute(
                    sql: "DELETE FROM imageIndex WHERE roomID = ? AND messageID IN (\(placeholders))",
                    arguments: StatementArguments(args)
                )
            } else {
                try db.execute(
                    sql: "DELETE FROM imageIndex WHERE messageID IN (\(placeholders))",
                    arguments: StatementArguments(messageIDs)
                )
            }
        }
    }
    
    /// Delete a single imageIndex row identified by (messageID, idx).
    /// If `roomID` is provided, the deletion is scoped to that room.
    func deleteImageIndexRow(forMessageID messageID: String, idx: Int, inRoom roomID: String? = nil) throws {
        try dbPool.write { db in
            if let roomID {
                try db.execute(
                    sql: "DELETE FROM imageIndex WHERE roomID = ? AND messageID = ? AND idx = ?",
                    arguments: [roomID, messageID, idx]
                )
            } else {
                try db.execute(
                    sql: "DELETE FROM imageIndex WHERE messageID = ? AND idx = ?",
                    arguments: [messageID, idx]
                )
            }
        }
    }
    
    // MARK: - Video Index Upsert
    private func upsertVideoIndex(for message: ChatMessage, in db: Database) throws {
        // 메시지 단위로 먼저 정리(멱등)
        try db.execute(
            sql: "DELETE FROM videoIndex WHERE roomID = ? AND messageID = ?",
            arguments: [message.roomID, message.ID]
        )
        
        let atts = message.attachments
            .filter { $0.type == .video }
            .sorted { $0.index < $1.index }
        
        guard !atts.isEmpty else { return }
        
        let when = message.sentAt ?? Date()
        
        for att in atts {
            try db.execute(sql: """
            INSERT OR REPLACE INTO videoIndex
            (roomID, messageID, idx,
             thumbKey, originalKey, thumbURL, originalURL,
             width, height, bytesOriginal,
             duration, approxBitrateMbps, preset,
             hash, isFailed, localThumb, sentAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
                           arguments: [
                            message.roomID,
                            message.ID,
                            att.index,
                            
                            // 이미지와 동일하게 hash를 키로 사용(없으면 nil)
                            att.hash.isEmpty ? nil : att.hash,
                            att.hash.isEmpty ? nil : (att.hash + ":orig"),
                            att.pathThumb.isEmpty ? nil : att.pathThumb,
                            att.pathOriginal.isEmpty ? nil : att.pathOriginal,
                            
                            att.width,
                            att.height,
                            att.bytesOriginal,
                            
                            /* duration */            nil, // Attachment에 없으면 nil
                            /* approxBitrateMbps */   nil,
                            /* preset */              nil,
                            
                            att.hash.isEmpty ? nil : att.hash,
                            message.isFailed,
                            message.isFailed ? (att.pathThumb.isEmpty ? nil : att.pathThumb) : nil,
                            when
                           ])
        }
    }
    
    func fetchVideoIndex(inRoom roomID: String, forMessageIDs ids: [String]) async throws -> [VideoIndexMeta] {
        guard !ids.isEmpty else { return [] }
        return try await dbPool.read { db in
            let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
            let sql = """
            SELECT roomID, messageID, idx, thumbKey, originalKey, thumbURL, originalURL,
                   width, height, bytesOriginal, duration, approxBitrateMbps, preset, hash, isFailed, localThumb, sentAt
              FROM videoIndex
             WHERE roomID = ?
               AND messageID IN (\(placeholders))
             ORDER BY sentAt ASC, messageID ASC, idx ASC
            """
            var args: [DatabaseValueConvertible] = [roomID]
            args.append(contentsOf: ids)
            return try VideoIndexMeta.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }
    }

    /// 방의 비디오 인덱스 총 개수
    func countVideoIndex(inRoom roomID: String) throws -> Int {
        try dbPool.read { db in
            try Int.fetchOne(db,
                             sql: "SELECT COUNT(*) FROM videoIndex WHERE roomID = ?",
                             arguments: [roomID]) ?? 0
        }
    }

    /// 최신순으로 방의 비디오 인덱스 페이지 조회 (DESC)
    func fetchLatestVideoIndex(inRoom roomID: String, limit: Int) throws -> [VideoIndexMeta] {
        try dbPool.read { db in
            try VideoIndexMeta.fetchAll(
                db,
                sql: """
                    SELECT roomID, messageID, idx, thumbKey, originalKey, thumbURL, originalURL,
                           width, height, bytesOriginal, duration, approxBitrateMbps, preset,
                           hash, isFailed, localThumb, sentAt
                      FROM videoIndex
                     WHERE roomID = ?
                     ORDER BY sentAt DESC, messageID DESC, idx ASC
                     LIMIT ?
                """,
                arguments: [roomID, limit]
            )
        }
    }

    /// 앵커 이전(과거) 비디오 인덱스 페이지 조회 (DESC 키셋 페이지네이션)
    func fetchOlderVideoIndex(inRoom roomID: String,
                              beforeSentAt: Date,
                              beforeMessageID: String,
                              limit: Int) throws -> [VideoIndexMeta] {
        try dbPool.read { db in
            try VideoIndexMeta.fetchAll(
                db,
                sql: """
                    SELECT roomID, messageID, idx, thumbKey, originalKey, thumbURL, originalURL,
                           width, height, bytesOriginal, duration, approxBitrateMbps, preset,
                           hash, isFailed, localThumb, sentAt
                      FROM videoIndex
                     WHERE roomID = ?
                       AND (sentAt < ? OR (sentAt = ? AND messageID < ?))
                     ORDER BY sentAt DESC, messageID DESC, idx ASC
                     LIMIT ?
                """,
                arguments: [roomID, beforeSentAt, beforeSentAt, beforeMessageID, limit]
            )
        }
    }
    
    //MARK: VideoIndex 삭제 관련 함수
    func deleteVideoIndex(forMessageID messageID: String, inRoom roomID: String? = nil) throws {
        try dbPool.write { db in
            if let roomID {
                try db.execute(
                    sql: "DELETE FROM videoIndex WHERE roomID = ? AND messageID = ?",
                    arguments: [roomID, messageID]
                )
            } else {
                try db.execute(
                    sql: "DELETE FROM videoIndex WHERE messageID = ?",
                    arguments: [messageID]
                )
            }
        }
    }
    
    func deleteVideoIndex(forMessageIDs messageIDs: [String], inRoom roomID: String? = nil) throws {
        guard !messageIDs.isEmpty else { return }
        let placeholders = Array(repeating: "?", count: messageIDs.count).joined(separator: ",")
        try dbPool.write { db in
            if let roomID {
                var args: [DatabaseValueConvertible] = [roomID]
                args.append(contentsOf: messageIDs)
                try db.execute(
                    sql: "DELETE FROM videoIndex WHERE roomID = ? AND messageID IN (\(placeholders))",
                    arguments: StatementArguments(args)
                )
            } else {
                try db.execute(
                    sql: "DELETE FROM videoIndex WHERE messageID IN (\(placeholders))",
                    arguments: StatementArguments(messageIDs)
                )
            }
        }
    }
    
    func deleteVideoIndexRow(forMessageID messageID: String, idx: Int, inRoom roomID: String? = nil) throws {
        try dbPool.write { db in
            if let roomID {
                try db.execute(
                    sql: "DELETE FROM videoIndex WHERE roomID = ? AND messageID = ? AND idx = ?",
                    arguments: [roomID, messageID, idx]
                )
            } else {
                try db.execute(
                    sql: "DELETE FROM videoIndex WHERE messageID = ? AND idx = ?",
                    arguments: [messageID, idx]
                )
            }
        }
    }
    
    /// Update duration fields for a specific videoIndex row (idempotent upsert-style update)
    func updateVideoDuration(inRoom roomID: String,
                             messageID: String,
                             idx: Int,
                             duration: Double,
                             durationMs: Int64,
                             durationText: String) throws {
        try dbPool.write { db in
            try db.execute(sql: """
                UPDATE videoIndex
                   SET duration = COALESCE(duration, ?),
                       durationMs = COALESCE(durationMs, ?),
                       durationText = COALESCE(durationText, ?)
                 WHERE roomID = ? AND messageID = ? AND idx = ?
            """,
            arguments: [duration, durationMs, durationText, roomID, messageID, idx])
        }
    }
    
    // MARK: - LocalUser & RoomMember API
    /// email, nickname, profileImagePath만을 다루는 경량 CRUD
    @discardableResult
    func upsertLocalUser(email: String, nickname: String, profileImagePath: String?) throws -> LocalUser {
        let user = LocalUser(email: email, nickname: nickname, profileImagePath: profileImagePath)
        try dbPool.write { db in
            try user.insert(db, onConflict: .replace)
        }
        return user
    }
    
    // MARK: RoomMember(신규) 멤버십 관리
    func addLocalUser(_ email: String, toRoom roomID: String) throws {
        let member = RoomMember(roomID: roomID, userEmail: email)
        try dbPool.write { db in
            try member.insert(db, onConflict: .replace)
        }
    }
    
    func removeLocalUser(_ email: String, fromRoom roomID: String) throws {
        try dbPool.write { db in
            _ = try RoomMember
                .filter(RoomMember.Columns.roomID == roomID && RoomMember.Columns.userEmail == email)
                .deleteAll(db)
        }
    }
    
    /// 방의 모든 사용자를 LocalUser로 반환 (닉네임 오름차순)
    func fetchLocalUsers(inRoom roomID: String) throws -> [LocalUser] {
        try dbPool.read { db in
            if try db.tableExists("RoomMember") {
                let sql = """
                SELECT u.*
                  FROM LocalUser u
                  JOIN RoomMember m ON m.userEmail = u.email
                 WHERE m.roomID = ?
                 ORDER BY u.nickname COLLATE NOCASE ASC
                """
                return try LocalUser.fetchAll(db, sql: sql, arguments: [roomID])
            } else {
                // 레거시 roomParticipant + userProfile 폴백 → LocalUser 형태로 매핑
                let sql = """
                SELECT up.email AS email,
                       COALESCE(up.nickname,'') AS nickname,
                       COALESCE(up.thumbPath, up.profileImagePath) AS profileImagePath
                  FROM userProfile up
                  JOIN roomParticipant rp ON rp.email = up.email
                 WHERE rp.roomId = ?
                 ORDER BY up.nickname COLLATE NOCASE ASC
                """
                let rows = try Row.fetchAll(db, sql: sql, arguments: [roomID])
                return rows.map { row in
                    LocalUser(email: row["email"], nickname: row["nickname"], profileImagePath: row["profileImagePath"])
                }
            }
        }
    }
    
    func fetchLocalUsersPage(roomID: String, offset: Int, limit: Int) throws -> ([LocalUser], Int) {
        try dbPool.read { db in
            let hasLocal = (try? db.tableExists("LocalUser")) == true && (try? db.tableExists("RoomMember")) == true
            if hasLocal {
                let list = try LocalUser.fetchAll(
                    db,
                    sql: """
                        SELECT u.*
                          FROM LocalUser u
                          JOIN RoomMember m ON m.userEmail = u.email
                         WHERE m.roomID = ?
                         ORDER BY u.nickname COLLATE NOCASE ASC
                         LIMIT ? OFFSET ?
                    """,
                    arguments: [roomID, limit, offset]
                )
                let total = try Int.fetchOne(db,
                    sql: "SELECT COUNT(*) FROM RoomMember WHERE roomID = ?",
                    arguments: [roomID]) ?? list.count
                return (list, total)
            } else if (try? db.tableExists("userProfile")) == true && (try? db.tableExists("roomParticipant")) == true {
                // Fallback: 레거시 테이블에서 최소 필드만 매핑
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT DISTINCT up.email AS email, COALESCE(up.nickname,'') AS nickname, up.profileImagePath AS profileImagePath
                          FROM userProfile up
                          JOIN roomParticipant rp ON up.email = rp.email
                         WHERE rp.roomId = ?
                         ORDER BY up.nickname COLLATE NOCASE ASC
                         LIMIT ? OFFSET ?
                    """,
                    arguments: [roomID, limit, offset]
                )
                let list = rows.map { row in
                    LocalUser(email: row["email"], nickname: row["nickname"], profileImagePath: row["profileImagePath"])
                }
                let total = try Int.fetchOne(db,
                    sql: "SELECT COUNT(DISTINCT email) FROM roomParticipant WHERE roomId = ?",
                    arguments: [roomID]) ?? list.count
                return (list, total)
            } else {
                return ([], 0)
            }
        }
    }
    
    /// 방의 모든 사용자 이메일을 반환
    /// - 신규 스키마(RoomMember) 우선, 레거시(roomParticipant) 폴백 지원
    func userEmails(in roomID: String) throws -> [String] {
        try dbPool.read { db in
            if try db.tableExists("RoomMember") {
                return try String.fetchAll(
                    db,
                    sql: "SELECT userEmail FROM RoomMember WHERE roomID = ?",
                    arguments: [roomID]
                )
            } else if try db.tableExists("roomParticipant") {
                return try String.fetchAll(
                    db,
                    sql: "SELECT email FROM roomParticipant WHERE roomId = ?",
                    arguments: [roomID]
                )
            } else {
                return []
            }
        }
    }
}
