//
//  Message.swift
//  OutPick
//
//  Created by 김가윤 on 9/25/24.
//

import SocketIO
import FirebaseFirestore

// 채팅 메시지 정보
struct ChatMessage: SocketData, Codable, Sendable {
    let ID: String
    let seq: Int64                    // 방 내 단조 증가 시퀀스(1,2,3,...) - 정렬/미읽음 계산용
    let roomID: String
    let senderUID: String                // 메시지 전송 사용자 아이디
    let senderEmail: String?             // 표시/디버깅용 snapshot. 권한 판단에는 사용하지 않는다.
    var senderNickname: String          // 메시지 전송 사용자 닉네임
    var senderAvatarPath: String? = nil // Storage 상대경로(예: "avatars/<uid>/v3.jpg")
    var messageType: ChatMessageType? = nil
    let msg: String?                    // 메시지 내용
    let sentAt: Date?                   // 메시지 보낸 시간
    var attachments: [Attachment]
    var sharedContent: LookbookSharedContent? = nil
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
        case seq
        case roomID
        case senderUID
        case senderEmail
        case senderNickname
        case senderAvatarPath
        case messageType
        case msg
        case sentAt
        case attachments
        case sharedContent
        case replyPreview
        case isFailed
        case isDeleted
    }
    
    func toSocketRepresentation() -> SocketData {
        var dict: [String: Any] = [
            "ID": ID,
            "roomID": roomID,
            "seq": seq,
            "senderUID": senderUID,
            "senderNickname": senderNickname,
            "msg": msg ?? "",
        ]
        if let senderEmail, !senderEmail.isEmpty {
            dict["senderEmail"] = senderEmail
        }
        if let messageType {
            dict["messageType"] = messageType.rawValue
        }
        if let avatar = senderAvatarPath, !avatar.isEmpty {
            dict["senderAvatarPath"] = avatar
        }
        
        dict["attachments"] = attachments.map { $0.toDict() }
        if let sharedContent {
            dict["sharedContent"] = sharedContent.toDict()
        }
        
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
        let searchIndex = ChatMessageSearchIndex.buildIndexedFields(from: msg)
        var dict: [String: Any] = [
            "ID": ID,
            "roomID": roomID,
            "seq": seq,
            "senderUID": senderUID,
            "senderNickname": senderNickname,
            "msg": msg ?? "",
            "sentAt": Timestamp(date: sentAt ?? Date()),
            "isDeleted": isDeleted,
            "searchNormalized": searchIndex.normalizedText,
            "searchChars": searchIndex.searchChars,
            "searchNgrams2": searchIndex.searchNgrams2,
            "searchIndexVersion": searchIndex.version
        ]
        if let senderEmail, !senderEmail.isEmpty {
            dict["senderEmail"] = senderEmail
        }
        if let messageType {
            dict["messageType"] = messageType.rawValue
        }
        if let avatar = senderAvatarPath, !avatar.isEmpty {
            dict["senderAvatarPath"] = avatar
        }

        dict["attachments"] = attachments.map { $0.toDict() }
        if let sharedContent {
            dict["sharedContent"] = sharedContent.toDict()
        }
        
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
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedMessageType: ChatMessageType? = {
            guard let rawValue = try? container.decodeIfPresent(String.self, forKey: .messageType) else {
                return nil
            }
            return ChatMessageType(legacyRawValue: rawValue)
        }()

        let decodedSharedContent: LookbookSharedContent? = {
            guard decodedMessageType == .lookbookShare else { return nil }
            return try? container.decodeIfPresent(LookbookSharedContent.self, forKey: .sharedContent)
        }()

        ID = try container.decode(String.self, forKey: .ID)
        seq = try container.decodeIfPresent(Int64.self, forKey: .seq) ?? 0
        roomID = try container.decode(String.self, forKey: .roomID)
        senderUID = try container.decode(String.self, forKey: .senderUID)
        senderEmail = try container.decodeIfPresent(String.self, forKey: .senderEmail)
        senderNickname = try container.decodeIfPresent(String.self, forKey: .senderNickname) ?? ""
        senderAvatarPath = try container.decodeIfPresent(String.self, forKey: .senderAvatarPath)
        messageType = decodedMessageType
        msg = try container.decodeIfPresent(String.self, forKey: .msg)
        sentAt = try container.decodeIfPresent(Date.self, forKey: .sentAt)
        attachments = try container.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        sharedContent = decodedSharedContent
        replyPreview = try container.decodeIfPresent(ReplyPreview.self, forKey: .replyPreview)
        isFailed = try container.decodeIfPresent(Bool.self, forKey: .isFailed) ?? false
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ID, forKey: .ID)
        try container.encode(seq, forKey: .seq)
        try container.encode(roomID, forKey: .roomID)
        try container.encode(senderUID, forKey: .senderUID)
        try container.encodeIfPresent(senderEmail, forKey: .senderEmail)
        try container.encode(senderNickname, forKey: .senderNickname)
        try container.encodeIfPresent(senderAvatarPath, forKey: .senderAvatarPath)
        try container.encodeIfPresent(messageType, forKey: .messageType)
        try container.encodeIfPresent(msg, forKey: .msg)
        try container.encodeIfPresent(sentAt, forKey: .sentAt)
        try container.encode(attachments, forKey: .attachments)
        try container.encodeIfPresent(sharedContent, forKey: .sharedContent)
        try container.encodeIfPresent(replyPreview, forKey: .replyPreview)
        try container.encode(isFailed, forKey: .isFailed)
        try container.encode(isDeleted, forKey: .isDeleted)
    }
}

extension ChatMessage {
    var sortedAttachments: [Attachment] {
        attachments.sorted { $0.index < $1.index }
    }

    var displayableAttachments: [Attachment] {
        sortedAttachments.filter(\.hasDisplayablePayload)
    }

    var displayableImageAttachments: [Attachment] {
        displayableAttachments.filter { $0.type == .image }
    }

    var displayableVideoAttachments: [Attachment] {
        displayableAttachments.filter { $0.type == .video }
    }

    var hasDisplayableAttachments: Bool {
        !displayableAttachments.isEmpty
    }

    var hasDisplayableImages: Bool {
        !displayableImageAttachments.isEmpty
    }

    var hasDisplayableVideos: Bool {
        !displayableVideoAttachments.isEmpty
    }

    var previewTextForRoomList: String {
        if let text = msg?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }

        let imageCount = attachments.filter { $0.type == .image }.count
        let videoCount = attachments.filter { $0.type == .video }.count
        switch (imageCount, videoCount) {
        case (let images, 0) where images > 0:
            return "사진 \(images)장"
        case (0, let videos) where videos > 0:
            return "동영상 \(videos)개"
        case (let images, let videos) where images > 0 && videos > 0:
            return "사진 \(images)장, 동영상 \(videos)개"
        default:
            return "(메시지)"
        }
    }

    static func from(_ dict: [String: Any]) -> ChatMessage? {
        // Required IDs
        guard let id = (dict["ID"] as? String) ?? (dict["id"] as? String) ?? (dict["messageID"] as? String), !id.isEmpty,
              let roomID = (dict["roomID"] as? String) ?? (dict["roomName"] as? String),
              let senderUID = dict["senderUID"] as? String else {
            return nil
        }

        // Sequence: accept Int/Int64/NSNumber/Double, fallback 0; also accept legacy "sequence"
        let seq: Int64 = {
            if let n = dict["seq"] as? NSNumber { return n.int64Value }
            if let i = dict["seq"] as? Int { return Int64(i) }
            if let i64 = dict["seq"] as? Int64 { return i64 }
            if let d = dict["seq"] as? Double { return Int64(d) }
            if let n = dict["sequence"] as? NSNumber { return n.int64Value }
            if let i = dict["sequence"] as? Int { return Int64(i) }
            if let i64 = dict["sequence"] as? Int64 { return i64 }
            if let d = dict["sequence"] as? Double { return Int64(d) }
            return 0
        }()

        // Nickname: support both keys. Default to empty if missing.
        let senderNickname = (dict["senderNickName"] as? String)
            ?? (dict["senderNickname"] as? String)
            ?? ""

        // Avatar path (optional). Prefer storage-relative path if provided; support legacy keys.
        let senderAvatarPath = (dict["senderAvatarPath"] as? String)
            ?? (dict["senderAvatarURL"] as? String)    // legacy url key if any

        // Message text may be empty
        let msg = (dict["msg"] as? String) ?? (dict["message"] as? String)
        let messageType = ChatMessageType(legacyRawValue: dict["messageType"] as? String)
        let sharedContent = messageType == .lookbookShare
            ? LookbookSharedContent.from(dict["sharedContent"])
            : nil

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
            seq: seq,
            roomID: roomID,
            senderUID: senderUID,
            senderEmail: dict["senderEmail"] as? String,
            senderNickname: senderNickname,
            senderAvatarPath: senderAvatarPath,
            messageType: messageType,
            msg: msg,
            sentAt: sentAt,
            attachments: attachments,
            sharedContent: sharedContent,
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
            guard let attachment = makeAttachment(from: item, fallbackIndex: i) else { continue }
            result.append(attachment)
        }

        if !result.isEmpty {
            return result
        }

        guard let rootAttachment = makeAttachment(from: dict, fallbackIndex: 0) else { return [] }
        return [rootAttachment]
    }

    private static func makeAttachment(from dict: [String: Any], fallbackIndex: Int) -> Attachment? {
        let pathThumb = normalizedPath(
            (dict["pathThumb"] as? String)
                ?? (dict["thumbPath"] as? String)
                ?? (dict["thumbnailPath"] as? String)
                ?? ""
        )
        let pathOriginal = normalizedPath(
            (dict["pathOriginal"] as? String)
                ?? (dict["originalPath"] as? String)
                ?? (dict["storagePath"] as? String)
                ?? (dict["url"] as? String)
                ?? (dict["originalUrl"] as? String)
                ?? ""
        )

        guard !pathThumb.isEmpty || !pathOriginal.isEmpty else {
            return nil
        }

        guard let type = attachmentType(from: dict, pathThumb: pathThumb, pathOriginal: pathOriginal) else {
            return nil
        }

        return Attachment(
            type: type,
            index: parseInt(dict["index"]) ?? fallbackIndex,
            pathThumb: pathThumb,
            pathOriginal: pathOriginal,
            width: parseInt(dict["w"]) ?? parseInt(dict["width"]) ?? 0,
            height: parseInt(dict["h"]) ?? parseInt(dict["height"]) ?? 0,
            bytesOriginal: parseInt(dict["bytesOriginal"]) ?? parseInt(dict["size"]) ?? parseInt(dict["sizeBytes"]) ?? 0,
            hash: (dict["hash"] as? String) ?? ((dict["messageID"] as? String) ?? UUID().uuidString.replacingOccurrences(of: "-", with: "")),
            blurhash: dict["blurhash"] as? String,
            duration: parseDouble(dict["duration"]),
            approxBitrateMbps: parseDouble(dict["approxBitrateMbps"]),
            preset: dict["preset"] as? String
        )
    }

    private static func attachmentType(
        from dict: [String: Any],
        pathThumb: String,
        pathOriginal: String
    ) -> Attachment.AttachmentType? {
        if let rawType = dict["type"] as? String,
           let type = Attachment.AttachmentType(rawValue: rawType) {
            return type
        }

        if dict["duration"] != nil {
            return .video
        }

        if !pathOriginal.isEmpty || !pathThumb.isEmpty {
            return .image
        }

        return nil
    }

    private static func normalizedPath(_ path: String) -> String {
        path.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private static func parseInt(_ value: Any?) -> Int? {
        switch value {
        case let n as NSNumber:
            return n.intValue
        case let i as Int:
            return i
        case let i64 as Int64:
            return Int(i64)
        case let d as Double:
            return Int(d)
        case let s as String:
            return Int(s)
        default:
            return nil
        }
    }

    private static func parseDouble(_ value: Any?) -> Double? {
        switch value {
        case let n as NSNumber:
            return n.doubleValue
        case let d as Double:
            return d
        case let i as Int:
            return Double(i)
        case let i64 as Int64:
            return Double(i64)
        case let s as String:
            return Double(s)
        default:
            return nil
        }
    }
}
