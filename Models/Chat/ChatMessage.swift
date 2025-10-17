//
//  Message.swift
//  OutPick
//
//  Created by 김가윤 on 9/25/24.
//

import UIKit
import FirebaseCore
import SocketIO
import FirebaseFirestore

struct ReplyPreview: Codable, Hashable {
    let messageID: String
    var sender: String
    var text: String
    var imagesCount: Int = 0
    var videosCount: Int = 0

    var attachmentsCount: Int { imagesCount + videosCount }
    var firstThumbPath: String? = nil
    var senderAvatarPath: String? = nil
    var sentAt: Date? = nil
    var isDeleted: Bool = false
}

struct VideoMetaPayload: Codable {
    let roomID: String
    let messageID: String
    let storagePath: String      // "videos/<room>/<msg>/video.mp4"
    let thumbnailPath: String    // "videos/<room>/<msg>/thumb.jpg"
    let duration: Double
    let width: Int
    let height: Int
    let sizeBytes: Int64
    let approxBitrateMbps: Double
    let preset: String           // "standard720" | "dataSaver720" | "high1080"
}

struct Attachment: Codable, Hashable {
    enum AttachmentType: String, Codable {
        case image
        case video
        // 필요한 경우 더 추가
    }

    // MARK: - Meta-only fields (no binary payloads)
    let type: AttachmentType
    let index: Int                       // 정렬 보장용
    let pathThumb: String                // Storage 경로 또는 상대 경로
    let pathOriginal: String             // Storage 경로 또는 상대 경로
    let width: Int                       // 원본 w
    let height: Int                      // 원본 h
    let bytesOriginal: Int               // 원본 바이트 수
    let hash: String                     // 콘텐츠 해시(파일명/캐시 키에 사용)
    var blurhash: String?                // 선택

    let duration: Double?

    // MARK: - Convenience (직렬화 제외)
    var thumbCacheKey: String { "att:\(hash):thumb" }
    var originalCacheKey: String { "att:\(hash):original" }

    // Socket/Firestore로 보낼 딕셔너리
    func toDict() -> [String: Any] {
        var dict: [String: Any] = [
            "type": type.rawValue,
            "index": index,
            "pathThumb": pathThumb,
            "pathOriginal": pathOriginal,
            "w": width,
            "h": height,
            "bytesOriginal": bytesOriginal,
            "hash": hash
        ]
        if let b = blurhash { dict["blurhash"] = b }
        if type == .video, let d = duration {
            dict["duration"] = d
        }
        return dict
    }

    // Hashable/Equatable
    func hash(into hasher: inout Hasher) {
        hasher.combine(type)
        hasher.combine(hash)
        hasher.combine(pathOriginal)
    }
    static func == (lhs: Attachment, rhs: Attachment) -> Bool {
        return lhs.type == rhs.type &&
               lhs.hash == rhs.hash &&
               lhs.pathOriginal == rhs.pathOriginal
    }
}

// 채팅 메시지 정보
struct ChatMessage: SocketData, Codable {
    let ID: String
    let roomID: String
    let senderID: String                // 메시지 전송 사용자 아이디
    let senderNickname: String          // 메시지 전송 사용자 닉네임
    var senderAvatarPath: String? = nil // Storage 상대경로(예: "avatars/<uid>/v3.jpg")
    let msg: String?                    // 메시지 내용
    let sentAt: Date?                   // 메시지 보낸 시간
    let attachments: [Attachment]
    var replyPreview: ReplyPreview?
    var isFailed: Bool = false
    var isDeleted: Bool = false

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    enum CodingKeys: String, CodingKey {
        case ID
        case roomID
        case senderID
        case senderNickname
        case senderAvatarPath
        case msg
        case sentAt
        case attachments
        case replyPreview
    }
    
    func toSocketRepresentation() -> SocketData {
        var dict: [String: Any] = [
            "ID": ID,
            "roomID": roomID,
            "senderID": senderID,
            "senderNickname": senderNickname,
            "msg": msg ?? "",
        ]
        if let avatar = senderAvatarPath, !avatar.isEmpty {
            dict["senderAvatarPath"] = avatar
        }
        
        dict["attachments"] = attachments.map { $0.toDict() }
        
        if let rp = replyPreview {
            var rpDict: [String: Any] = [
                "messageID": rp.messageID,
                "sender": rp.sender,
                "text": rp.text,
                "isDeleted": rp.isDeleted,
                "imagesCount": rp.imagesCount,
                "videosCount": rp.videosCount
            ]
            if let avatar = rp.senderAvatarPath, !avatar.isEmpty {
                rpDict["senderAvatarPath"] = avatar
            }
            if let t = rp.sentAt {
                rpDict["sentAt"] = ChatMessage.iso8601Formatter.string(from: t)
            }
            if let thumb = rp.firstThumbPath, !thumb.isEmpty {
                rpDict["firstThumbPath"] = thumb
            }
            dict["replyPreview"] = rpDict
        }
        
        if let sentAt = sentAt {
            dict["sentAt"] = ChatMessage.iso8601Formatter.string(from: sentAt)
        }
        
        return dict
    }
    
    // Firestore에 저장하기 위힌 뱐환 메서드
    func toDict() -> [String: Any] {
        var dict: [String: Any] = [
            "ID": ID,
            "roomID": roomID,
            "senderID": senderID,
            "senderNickname": senderNickname,
            "msg": msg ?? "",
            "sentAt": Timestamp(date: sentAt ?? Date()),
            "isDeleted": isDeleted
        ]
        if let avatar = senderAvatarPath, !avatar.isEmpty {
            dict["senderAvatarPath"] = avatar
        }

        dict["attachments"] = attachments.map { $0.toDict() }
        
        if let rp = replyPreview {
            var rpDict: [String: Any] = [
                "messageID": rp.messageID,
                "sender": rp.sender,
                "text": rp.text,
                "isDeleted": rp.isDeleted,
                "imagesCount": rp.imagesCount,
                "videosCount": rp.videosCount
            ]
            if let avatar = rp.senderAvatarPath, !avatar.isEmpty {
                rpDict["senderAvatarPath"] = avatar
            }
            if let t = rp.sentAt {
                rpDict["sentAt"] = Timestamp(date: t)
            }
            if let thumb = rp.firstThumbPath, !thumb.isEmpty {
                rpDict["firstThumbPath"] = thumb
            }
            dict["replyPreview"] = rpDict
        }
        
        return dict
    }
    
    func hash(into hasher: inout Hasher) { hasher.combine(ID) }
    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        return lhs.ID == rhs.ID
    }
}

extension ChatMessage: Hashable {}

extension ChatMessage {
    static func from(_ dict: [String: Any]) -> ChatMessage? {
        // Required IDs
        guard let id = (dict["ID"] as? String) ?? (dict["id"] as? String), !id.isEmpty,
              let roomID = dict["roomID"] as? String,
              let senderID = dict["senderID"] as? String else {
            return nil
        }

        // Nickname: support both keys. Default to empty if missing.
        let senderNickname = (dict["senderNickName"] as? String)
            ?? (dict["senderNickname"] as? String)
            ?? ""

        // Avatar path (optional). Prefer storage-relative path if provided; support legacy keys.
        let senderAvatarPath = (dict["senderAvatarPath"] as? String)
            ?? (dict["senderAvatarURL"] as? String)    // legacy url key if any

        // Message text may be empty
        let msg = dict["msg"] as? String

        // sentAt: accept ISO8601(with/without fractional), Timestamp, epoch(s/ms). Optional.
        let sentAt = parseSentAt(dict["sentAt"]) ?? parseSentAt(dict["createdAt"]) // fallback key if any

        // Reply preview (optional)
        var rp: ReplyPreview? = nil
        if let rpDict = dict["replyPreview"] as? [String: Any],
           let mid = rpDict["messageID"] as? String, !mid.isEmpty {
            let sentAtPreview = parseSentAt(rpDict["sentAt"]) // accepts ISO8601/Timestamp/epoch

            // New fields first
            var images = rpDict["imagesCount"] as? Int
            var videos = rpDict["videosCount"] as? Int

            // Backward compatibility: legacy `attachmentsCount`
            if images == nil && videos == nil, let legacy = rpDict["attachmentsCount"] as? Int {
                images = legacy
                videos = 0
            }

            rp = ReplyPreview(
                messageID: mid,
                sender: rpDict["sender"] as? String ?? "",
                text: rpDict["text"] as? String ?? "",
                imagesCount: images ?? 0,
                videosCount: videos ?? 0,
                firstThumbPath: (rpDict["firstThumbPath"] as? String),
                senderAvatarPath: (rpDict["senderAvatarPath"] as? String),
                sentAt: sentAtPreview,
                isDeleted: rpDict["isDeleted"] as? Bool ?? false
            )
        }

        // Attachments (meta-only)
        let attachments = ChatMessage.parseAttachments(from: dict)

        // Flags (optional)
        let isFailed = dict["isFailed"] as? Bool ?? false
        let isDeleted = dict["isDeleted"] as? Bool ?? false

        return ChatMessage(
            ID: id,
            roomID: roomID,
            senderID: senderID,
            senderNickname: senderNickname,
            senderAvatarPath: senderAvatarPath,
            msg: msg,
            sentAt: sentAt,
            attachments: attachments,
            replyPreview: rp,
            isFailed: isFailed,
            isDeleted: isDeleted
        )
    }

    // Parse attachments/images from socket payload (supports Data or base64 for thumbData)
    private static func parseAttachments(from dict: [String: Any]) -> [Attachment] {
        // 기본은 "attachments" 키, 레거시는 "images" 키도 허용
        let rawArray = (dict["attachments"] as? [Any]) ?? (dict["images"] as? [Any]) ?? []
        var result: [Attachment] = []
        result.reserveCapacity(rawArray.count)

        for (i, any) in rawArray.enumerated() {
            guard let item = any as? [String: Any] else { continue }

            // 타입
            let typeStr = (item["type"] as? String) ?? "image"
            let type = Attachment.AttachmentType(rawValue: typeStr) ?? .image

            // 필수 메타 (경로/정렬/크기)
            let index = item["index"] as? Int ?? i
            let pathThumb = (item["pathThumb"] as? String) ?? (item["thumbPath"] as? String) ?? ""
            // pathOriginal은 Storage 상대경로가 표준이지만, 레거시 url/originalUrl 문자열도 임시 허용
            let pathOriginal = (item["pathOriginal"] as? String)
                ?? (item["originalPath"] as? String)
                ?? (item["url"] as? String)
                ?? (item["originalUrl"] as? String)
                ?? ""

            let width  = (item["w"] as? Int) ?? (item["width"] as? Int) ?? 0
            let height = (item["h"] as? Int) ?? (item["height"] as? Int) ?? 0
            let bytes  = (item["bytesOriginal"] as? Int) ?? (item["size"] as? Int) ?? 0
            let hash   = (item["hash"] as? String) ?? UUID().uuidString.replacingOccurrences(of: "-", with: "")
            let blur   = item["blurhash"] as? String

            var duration: Double? = nil
            if let d = item["duration"] as? Double { duration = d }
            else if let i = item["duration"] as? Int { duration = Double(i) }

            result.append(Attachment(
                type: type,
                index: index,
                pathThumb: pathThumb,
                pathOriginal: pathOriginal,
                width: width,
                height: height,
                bytesOriginal: bytes,
                hash: hash,
                blurhash: blur,
                duration: duration
            ))
        }
        return result
    }
}

extension ChatMessage {
    // MARK: - Date Parsers
    fileprivate static let iso8601WithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    fileprivate static let iso8601NoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    fileprivate static let fallbackDateFormatter1: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return f
    }()

    fileprivate static let fallbackDateFormatter2: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return f
    }()
    
    /// Accepts multiple payload shapes from Socket/Firestore:
    /// String(ISO8601 with/without fractional), Timestamp, seconds(Double/Int), or ms epoch.
    private static func parseSentAt(_ value: Any?) -> Date? {
        // Fast path by type
        switch value {
        case let ts as Timestamp:
            return ts.dateValue()
        case let d as Double:
            return Date(timeIntervalSince1970: d > 3_000_000_000 ? d / 1000.0 : d)
        case let i as Int:
            let d = Double(i)
            return Date(timeIntervalSince1970: d > 3_000_000_000 ? d / 1000.0 : d)
        case let s as String:
            // 1) ISO8601 with fractional seconds (e.g., 2025-09-26T17:57:57.403Z)
            if let d = ChatMessage.iso8601WithFractional.date(from: s) { return d }
            // 2) ISO8601 without fractional seconds
            if let d = ChatMessage.iso8601NoFraction.date(from: s) { return d }
            // 3) Custom fallback using existing formatter if present
            if let d = ChatMessage.iso8601Formatter.date(from: s) { return d }
            // 4) Common RFC3339-like patterns
            if let d = ChatMessage.fallbackDateFormatter1.date(from: s) { return d }
            if let d = ChatMessage.fallbackDateFormatter2.date(from: s) { return d }
            return nil
        default:
            return nil
        }
    }
}
