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

final class GRDBManager: ChatOutgoingOutboxPersisting {
    static let shared = GRDBManager()
    let dbPool: DatabasePool

    static func registerBaseUserMigrations(_ migrator: inout DatabaseMigrator) {
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
            guard try db.tableExists("userProfile") else { return }

            let profileImageExpression = try userProfileImageBackfillExpression(in: db)
            try db.execute(sql: """
                INSERT OR IGNORE INTO LocalUser (email, nickname, profileImagePath)
                SELECT email, COALESCE(nickname, ''), \(profileImageExpression)
                  FROM userProfile
            """)
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
    }

    private static func userProfileImageBackfillExpression(in db: Database) throws -> String {
        let columnRows = try Row.fetchAll(db, sql: "PRAGMA table_info(userProfile)")
        let columns = Set(columnRows.compactMap { $0["name"] as String? })

        switch (columns.contains("thumbPath"), columns.contains("profileImagePath")) {
        case (true, true):
            return "COALESCE(thumbPath, profileImagePath)"
        case (true, false):
            return "thumbPath"
        case (false, true):
            return "profileImagePath"
        case (false, false):
            return "NULL"
        }
    }

    private init() {
        // DB 파일 경로 설정
        let databaseURL = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("OutPick.sqlite")
        // DatabasePool 생성 (멀티스레드 대응)
        dbPool = try! DatabasePool(path: databaseURL.path)

        // 마이그레이션 수행
        var migrator = DatabaseMigrator()
        Self.registerBaseUserMigrations(&migrator)
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
                t.column("senderUID", .text).notNull()
                t.column("senderEmail", .text)
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

        migrator.registerMigration("migrateChatMessageSenderUID") { db in
            do {
                try db.alter(table: "chatMessage") { t in
                    t.add(column: "senderUID", .text)
                    t.add(column: "senderEmail", .text)
                }
            } catch {
                print("[Migration] migrateChatMessageSenderUID (add columns) skipped or failed: \(error)")
            }
            do {
                try db.execute(sql: """
                    UPDATE chatMessage
                       SET senderUID = COALESCE(NULLIF(senderUID, ''), senderID)
                     WHERE senderUID IS NULL OR senderUID = ''
                """)
            } catch {
                print("[Migration] migrateChatMessageSenderUID (backfill senderUID) skipped or failed: \(error)")
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

        migrator.registerMigration("addLookbookShareToChatMessage") { db in
            do {
                try db.alter(table: "chatMessage") { t in
                    t.add(column: "messageType", .text)
                    t.add(column: "sharedContent", .text)
                }
            } catch {
                print("[Migration] addLookbookShareToChatMessage skipped or failed: \(error)")
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

        migrator.registerMigration("createChatOutgoingOutbox") { db in
            try db.create(table: "chatOutgoingOutbox", options: [.ifNotExists]) { t in
                t.column("messageID", .text).primaryKey()
                t.column("roomID", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("stage", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("localPayloadJSON", .text)
                t.column("uploadedPayloadJSON", .text)
                t.column("lastError", .text)
            }
            try db.create(index: "idx_chatOutgoingOutbox_room_updated",
                          on: "chatOutgoingOutbox",
                          columns: ["roomID", "updatedAt"],
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
    
    
    // MARK: 메시지
    /// 여러 메시지를 한 번에 저장하고, 마지막에만 조건부 pruneMessages 실행
    func saveChatMessages(_ messages: [ChatMessage]) async throws {
        guard !messages.isEmpty else { return }
        
        // Write messages + image index (same transaction per write block)
        try await dbPool.write { db in
            for message in messages {
                // 1) Validate required fields (skip invalid rows to honor NOT NULL constraints)
                guard !message.roomID.isEmpty,
                      !message.senderUID.isEmpty,
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

                let sharedContentJSON: String? = {
                    guard let sharedContent = message.sharedContent else { return nil }
                    do {
                        let data = try JSONEncoder().encode(sharedContent)
                        return String(data: data, encoding: .utf8)
                    } catch {
                        print("sharedContent JSON 인코딩 실패: \(error)")
                        return nil
                    }
                }()

                // 4) Upsert chatMessage row
                try db.execute(
                    sql: """
                    INSERT OR REPLACE INTO chatMessage
                    (id, seq, roomID, senderUID, senderEmail, senderNickname, senderAvatarPath, messageType, msg, sentAt, attachments, sharedContent, isFailed, replyPreview, isDeleted)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        message.ID,
                        message.seq,
                        message.roomID,
                        message.senderUID,
                        message.senderEmail,
                        message.senderNickname,
                        message.senderAvatarPath,
                        message.messageType?.rawValue,
                        message.msg,
                        message.sentAt,
                        attachmentsJSON,
                        sharedContentJSON,
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
                
                if message.isDeleted {
                    try db.execute(
                        sql: "DELETE FROM imageIndex WHERE roomID = ? AND messageID = ?",
                        arguments: [message.roomID, message.ID]
                    )
                    try db.execute(
                        sql: "DELETE FROM videoIndex WHERE roomID = ? AND messageID = ?",
                        arguments: [message.roomID, message.ID]
                    )
                } else {
                    // 6) Image index upsert for this message (meta only)
                    try self.upsertImageIndex(for: message, in: db)
                    
                    // 6b) Video index upsert for this message (meta only)
                    try self.upsertVideoIndex(for: message, in: db)
                }
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

    func fetchMessage(id messageID: String, inRoom roomID: String) async throws -> ChatMessage? {
        try await dbPool.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM chatMessage WHERE roomID = ? AND id = ? LIMIT 1",
                arguments: [roomID, messageID]
            ) else {
                return nil
            }
            return try self.makeChatMessage(from: row)
        }
    }

    func fetchFailedOutgoingMessages(inRoom roomID: String, senderUID: String) async throws -> [ChatMessage] {
        try await dbPool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT chatMessage.*,
                       chatOutgoingOutbox.kind AS outboxKind,
                       chatOutgoingOutbox.localPayloadJSON AS outboxLocalPayloadJSON,
                       chatOutgoingOutbox.uploadedPayloadJSON AS outboxUploadedPayloadJSON
                FROM chatMessage
                LEFT JOIN chatOutgoingOutbox
                  ON chatOutgoingOutbox.messageID = chatMessage.id
                WHERE chatMessage.roomID = ?
                  AND chatMessage.senderUID = ?
                  AND chatMessage.isFailed = 1
                  AND chatMessage.isDeleted = 0
                ORDER BY chatMessage.sentAt ASC, chatMessage.id ASC
                """,
                arguments: [roomID, senderUID]
            )
            return try rows.map { row in
                var message = try self.makeChatMessage(from: row)
                message.attachments = self.stableFailedOutgoingAttachments(from: row, fallback: message.attachments)
                return message
            }
        }
    }

    func hardDeleteMessage(id messageID: String, inRoom roomID: String) async throws {
        try await dbPool.write { db in
            try db.execute(sql: "DELETE FROM chatMessage WHERE roomID = ? AND id = ?", arguments: [roomID, messageID])
            try db.execute(sql: "DELETE FROM imageIndex WHERE roomID = ? AND messageID = ?", arguments: [roomID, messageID])
            try db.execute(sql: "DELETE FROM videoIndex WHERE roomID = ? AND messageID = ?", arguments: [roomID, messageID])
            try db.execute(sql: "DELETE FROM chatMessageFTS WHERE roomID = ? AND id = ?", arguments: [roomID, messageID])
        }
    }

    func saveOutgoingOutboxRecord(_ record: ChatOutgoingOutboxRecord) async throws {
        try await dbPool.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO chatOutgoingOutbox
                (messageID, roomID, kind, stage, createdAt, updatedAt, localPayloadJSON, uploadedPayloadJSON, lastError)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    record.messageID,
                    record.roomID,
                    record.kind.rawValue,
                    record.stage.rawValue,
                    record.createdAt,
                    record.updatedAt,
                    record.localPayloadJSON,
                    record.uploadedPayloadJSON,
                    record.lastError
                ]
            )
        }
    }

    func fetchOutgoingOutboxRecord(messageID: String) async throws -> ChatOutgoingOutboxRecord? {
        try await dbPool.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM chatOutgoingOutbox WHERE messageID = ? LIMIT 1",
                arguments: [messageID]
            ) else {
                return nil
            }
            return ChatOutgoingOutboxRecord(
                messageID: row["messageID"],
                roomID: row["roomID"],
                kind: ChatOutgoingOutboxKind(rawValue: row["kind"] as String) ?? .text,
                stage: ChatOutgoingOutboxStage(rawValue: row["stage"] as String) ?? .failed,
                createdAt: row["createdAt"],
                updatedAt: row["updatedAt"],
                localPayloadJSON: row["localPayloadJSON"],
                uploadedPayloadJSON: row["uploadedPayloadJSON"],
                lastError: row["lastError"]
            )
        }
    }

    func deleteOutgoingOutboxRecord(messageID: String) async throws {
        try await dbPool.write { db in
            try db.execute(sql: "DELETE FROM chatOutgoingOutbox WHERE messageID = ?", arguments: [messageID])
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

    private func makeChatMessage(from row: Row) throws -> ChatMessage {
        let attachmentsJSON = row["attachments"] as? String ?? "[]"
        let attachments = try JSONDecoder().decode([Attachment].self, from: Data(attachmentsJSON.utf8))
        let replyPreview = decodeJSON(ReplyPreview.self, from: row["replyPreview"] as? String)
        let messageType = ChatMessageType(legacyRawValue: row["messageType"] as? String)
        let sharedContent: LookbookSharedContent? = {
            guard messageType == .lookbookShare else { return nil }
            return decodeJSON(LookbookSharedContent.self, from: row["sharedContent"] as? String)
        }()

        return ChatMessage(
            ID: row["id"],
            seq: (row["seq"] as? Int64) ?? 0,
            roomID: row["roomID"],
            senderUID: row["senderUID"],
            senderEmail: row["senderEmail"] as? String,
            senderNickname: row["senderNickname"],
            senderAvatarPath: row["senderAvatarPath"] as? String,
            messageType: messageType,
            msg: row["msg"],
            sentAt: row["sentAt"],
            attachments: attachments,
            sharedContent: sharedContent,
            replyPreview: replyPreview,
            isFailed: boolValue(row["isFailed"]),
            isDeleted: boolValue(row["isDeleted"])
        )
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, from json: String?) -> T? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func stableFailedOutgoingAttachments(from row: Row, fallback: [Attachment]) -> [Attachment] {
        guard let rawKind = row["outboxKind"] as? String,
              let kind = ChatOutgoingOutboxKind(rawValue: rawKind) else {
            return fallback
        }
        switch kind {
        case .text:
            return fallback
        case .images:
            if let uploaded = decodeJSON(
                ChatOutgoingOutboxUploadedImagesPayload.self,
                from: row["outboxUploadedPayloadJSON"] as? String
            ), !uploaded.attachments.isEmpty {
                return uploaded.attachments
            }
            if let local = decodeJSON(
                ChatOutgoingOutboxImagePayload.self,
                from: row["outboxLocalPayloadJSON"] as? String
            ) {
                return local.items.sorted(by: { $0.index < $1.index }).map { item in
                    Attachment(
                        type: .image,
                        index: item.index,
                        pathThumb: currentOutboxDisplayPath(from: item.thumbFilePath),
                        pathOriginal: currentOutboxDisplayPath(from: item.originalFilePath),
                        width: item.originalWidth,
                        height: item.originalHeight,
                        bytesOriginal: item.bytesOriginal,
                        hash: item.sha256,
                        blurhash: nil,
                        duration: nil
                    )
                }
            }
            return fallback
        case .video:
            if let uploaded = decodeJSON(
                VideoMetaPayload.self,
                from: row["outboxUploadedPayloadJSON"] as? String
            ) {
                return [
                    Attachment(
                        type: .video,
                        index: 0,
                        pathThumb: uploaded.thumbnailPath,
                        pathOriginal: uploaded.storagePath,
                        width: uploaded.width,
                        height: uploaded.height,
                        bytesOriginal: Int(uploaded.sizeBytes),
                        hash: uploaded.messageID,
                        blurhash: nil,
                        duration: uploaded.duration,
                        approxBitrateMbps: uploaded.approxBitrateMbps,
                        preset: uploaded.preset
                    )
                ]
            }
            if let local = decodeJSON(
                ChatOutgoingOutboxVideoPayload.self,
                from: row["outboxLocalPayloadJSON"] as? String
            ) {
                return [
                    Attachment(
                        type: .video,
                        index: 0,
                        pathThumb: currentOutboxDisplayPath(from: local.thumbnailFilePath),
                        pathOriginal: currentOutboxDisplayPath(from: local.compressedFilePath),
                        width: local.width,
                        height: local.height,
                        bytesOriginal: Int(local.sizeBytes),
                        hash: local.sha256,
                        blurhash: nil,
                        duration: local.duration,
                        approxBitrateMbps: local.approxBitrateMbps,
                        preset: local.preset
                    )
                ]
            }
            return fallback
        }
    }

    private func currentOutboxDisplayPath(from storedPath: String) -> String {
        let trimmed = storedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return storedPath }
        let fileManager = FileManager.default
        guard let root = try? fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("ChatOutgoingOutbox", isDirectory: true) else {
            return storedPath
        }

        if trimmed.hasPrefix("file://"),
           let url = URL(string: trimmed),
           url.isFileURL {
            if fileManager.fileExists(atPath: url.path) {
                return url.path
            }
            return migratedOutboxPath(fromAbsolutePath: url.path, root: root) ?? storedPath
        }

        if trimmed.hasPrefix("/") {
            if fileManager.fileExists(atPath: trimmed) {
                return trimmed
            }
            return migratedOutboxPath(fromAbsolutePath: trimmed, root: root) ?? storedPath
        }

        return root.appendingPathComponent(trimmed).path
    }

    private func migratedOutboxPath(fromAbsolutePath path: String, root: URL) -> String? {
        guard let range = path.range(of: "ChatOutgoingOutbox/") else { return nil }
        let relative = String(path[range.upperBound...])
        let url = root.appendingPathComponent(relative)
        return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
    }

    private func boolValue(_ value: Any?) -> Bool {
        switch value {
        case let bool as Bool:
            return bool
        case let int as Int:
            return int == 1
        case let int64 as Int64:
            return int64 == 1
        case let number as NSNumber:
            return number.boolValue
        default:
            return false
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
            
            return try ascRows.map { try self.makeChatMessage(from: $0) }
        }
    }

    func fetchMessagesAfterSeq(inRoom roomID: String, afterSeq: Int64, limit: Int) async throws -> [ChatMessage] {
        try await dbPool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM chatMessage
                WHERE roomID = ?
                  AND seq > ?
                ORDER BY seq ASC, id ASC
                LIMIT ?
                """,
                arguments: [roomID, afterSeq, limit]
            )

            return try rows.map { try self.makeChatMessage(from: $0) }
        }
    }

    func fetchMessagesBeforeSeq(inRoom roomID: String, beforeSeq: Int64, limit: Int) async throws -> [ChatMessage] {
        try await dbPool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM chatMessage
                WHERE roomID = ?
                  AND seq < ?
                ORDER BY seq DESC, id DESC
                LIMIT ?
                """,
                arguments: [roomID, beforeSeq, limit]
            )

            let ascRows = rows.reversed()

            return try ascRows.map { try self.makeChatMessage(from: $0) }
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
            
            return try ascRows.map { try self.makeChatMessage(from: $0) }
        }
    }

    func fetchNewerMessages(inRoom roomID: String, after anchorMessageID: String, limit: Int) async throws -> [ChatMessage] {
        try await dbPool.read { db in
            guard let anchorRow = try Row.fetchOne(
                db,
                sql: "SELECT id, seq FROM chatMessage WHERE roomID = ? AND id = ? LIMIT 1",
                arguments: [roomID, anchorMessageID]
            ) else {
                return []
            }
            let anchorSeq: Int64 = (anchorRow["seq"] as? Int64) ?? 0

            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM chatMessage
                WHERE roomID = ?
                  AND seq > ?
                ORDER BY seq ASC, id ASC
                LIMIT ?
                """,
                arguments: [roomID, anchorSeq, limit]
            )

            return try rows.map { try self.makeChatMessage(from: $0) }
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
            
            return try rows.map { try self.makeChatMessage(from: $0) }
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
            
            return try rows.map { try self.makeChatMessage(from: $0) }
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
            try db.execute(sql: "DELETE FROM videoIndex WHERE roomID = ?", arguments: [roomID])
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

    func upsertMediaIndexEntries(_ entries: [ChatRoomMediaIndexEntry]) throws {
        guard !entries.isEmpty else { return }

        try dbPool.write { db in
            for entry in entries {
                switch entry.type {
                case .image:
                    try db.execute(sql: """
                        INSERT OR REPLACE INTO imageIndex
                        (roomID, messageID, idx, thumbKey, originalKey, thumbURL, originalURL, width, height, bytesOriginal, hash, isFailed, localThumb, sentAt)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                                   arguments: [
                                    entry.roomID,
                                    entry.messageID,
                                    entry.idx,
                                    entry.thumbKey,
                                    entry.originalKey,
                                    entry.thumbURL,
                                    entry.originalURL,
                                    entry.width,
                                    entry.height,
                                    entry.bytesOriginal,
                                    entry.hash,
                                    false,
                                    nil,
                                    entry.sentAt
                                   ])

                case .video:
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
                                    entry.roomID,
                                    entry.messageID,
                                    entry.idx,
                                    entry.thumbKey,
                                    entry.originalKey,
                                    entry.thumbURL,
                                    entry.originalURL,
                                    entry.width,
                                    entry.height,
                                    entry.bytesOriginal,
                                    entry.duration,
                                    nil,
                                    nil,
                                    entry.hash,
                                    false,
                                    nil,
                                    entry.sentAt
                                   ])
                }
            }
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
                            
                            att.duration,
                            att.approxBitrateMbps,
                            att.preset,
                            
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
    func deleteLocalRoomDataAndPruneUsers(roomID: String) throws {
        try dbPool.write { db in
            // 1) 이 방의 로컬 데이터 삭제
            try deleteLocalRoomData(in: db, roomID: roomID)

            // 2) 참조 없는 LocalUser 정리
            try pruneOrphanLocalUsers(in: db)
        }
    }
    
    func deleteLocalRoomData(in db: Database, roomID: String) throws {
        // 1) 메시지 / 첨부 / FTS
        try db.execute(
            sql: "DELETE FROM chatMessage WHERE roomID = ?",
            arguments: [roomID]
        )
        try db.execute(
            sql: "DELETE FROM imageIndex WHERE roomID = ?",
            arguments: [roomID]
        )
        try db.execute(
            sql: "DELETE FROM videoIndex WHERE roomID = ?",
            arguments: [roomID]
        )
        // chatMessageFTS는 roomID 컬럼을 가지고 있으므로 roomID 기준으로 정리
        try db.execute(
            sql: "DELETE FROM chatMessageFTS WHERE roomID = ?",
            arguments: [roomID]
        )

        // 2) 방과 연관된 기타 로컬 테이블 정리 (있을 때만)
        if try db.tableExists("roomImage") {
            try db.execute(
                sql: "DELETE FROM roomImage WHERE roomId = ?",
                arguments: [roomID]
            )
        }

        // 3) 이 방 기준 참여자 관계 삭제
        if try db.tableExists("RoomMember") {
            try db.execute(
                sql: "DELETE FROM RoomMember WHERE roomID = ?",
                arguments: [roomID]
            )
        }
        // 레거시 roomParticipant도 함께 정리
        if try db.tableExists("roomParticipant") {
            try db.execute(
                sql: "DELETE FROM roomParticipant WHERE roomId = ?",
                arguments: [roomID]
            )
        }
    }
    
    func pruneOrphanLocalUsers(in db: Database) throws {
        let myEmail = LoginManager.shared.getUserEmail

        // RoomMember 테이블이 없으면 굳이 정리할 수 있는 정보가 없으므로 스킵
        guard (try? db.tableExists("RoomMember")) == true else { return }

        // 나 자신은 항상 유지하고,
        // 어떤 RoomMember에도 등장하지 않는 email만 삭제
        try db.execute(
            sql: """
            DELETE FROM LocalUser
            WHERE email != ?
              AND email NOT IN (
                    SELECT DISTINCT userEmail
                    FROM RoomMember
              )
            """,
            arguments: [myEmail]
        )
    }
    
    func upsertLocalUser(email: String, nickname: String, profileImagePath: String?) throws -> LocalUser {
        let user = LocalUser(email: email, nickname: nickname, profileImagePath: profileImagePath)
        try dbPool.write { db in
            try user.insert(db, onConflict: .replace)
        }
        return user
    }

    func fetchLocalUser(email: String) throws -> LocalUser? {
        try dbPool.read { db in
            try LocalUser.fetchOne(db, key: email)
        }
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
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT LOWER(m.userEmail) AS email,
                               COALESCE(MAX(NULLIF(u.nickname, '')), LOWER(m.userEmail)) AS nickname,
                               MAX(u.profileImagePath) AS profileImagePath
                          FROM RoomMember m
                          LEFT JOIN LocalUser u ON LOWER(u.email) = LOWER(m.userEmail)
                         WHERE m.roomID = ?
                         GROUP BY LOWER(m.userEmail)
                         ORDER BY nickname COLLATE NOCASE ASC,
                                  email COLLATE NOCASE ASC
                    """,
                    arguments: [roomID]
                )
                return rows.map { row in
                    LocalUser(
                        email: row["email"],
                        nickname: row["nickname"],
                        profileImagePath: row["profileImagePath"]
                    )
                }
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
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT LOWER(m.userEmail) AS email,
                               COALESCE(MAX(NULLIF(u.nickname, '')), LOWER(m.userEmail)) AS nickname,
                               MAX(u.profileImagePath) AS profileImagePath
                          FROM RoomMember m
                          LEFT JOIN LocalUser u ON LOWER(u.email) = LOWER(m.userEmail)
                         WHERE m.roomID = ?
                         GROUP BY LOWER(m.userEmail)
                         ORDER BY nickname COLLATE NOCASE ASC,
                                  email COLLATE NOCASE ASC
                         LIMIT ? OFFSET ?
                    """,
                    arguments: [roomID, limit, offset]
                )
                let list = rows.map { row in
                    LocalUser(
                        email: row["email"],
                        nickname: row["nickname"],
                        profileImagePath: row["profileImagePath"]
                    )
                }
                let total = try Int.fetchOne(db,
                    sql: "SELECT COUNT(DISTINCT LOWER(userEmail)) FROM RoomMember WHERE roomID = ?",
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
