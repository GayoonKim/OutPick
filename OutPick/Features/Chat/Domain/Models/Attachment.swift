//
//  Attachment.swift
//  OutPick
//
//  Created by Codex on 6/16/26.
//

import Foundation

struct Attachment: Codable, Hashable, Sendable {
    enum AttachmentType: String, Codable, Sendable {
        case image
        case video
        // 필요한 경우 더 추가
    }

    // MARK: - Meta-only fields (no binary payloads)
    let attachmentID: String?
    let type: AttachmentType
    let index: Int                       // 정렬 보장용
    let bucketThumb: String?
    let bucketOriginal: String?
    let pathThumb: String                // Storage 경로 또는 상대 경로
    let pathOriginal: String             // Storage 경로 또는 상대 경로
    let width: Int                       // 원본 w
    let height: Int                      // 원본 h
    let bytesOriginal: Int               // 원본 바이트 수
    let hash: String                     // 콘텐츠 해시(파일명/캐시 키에 사용)
    var blurhash: String?                // 선택

    let duration: Double?
    let approxBitrateMbps: Double?
    let preset: String?
    let mediaFormat: String?
    let isAnimated: Bool?

    init(
        attachmentID: String? = nil,
        type: AttachmentType,
        index: Int,
        bucketThumb: String? = nil,
        bucketOriginal: String? = nil,
        pathThumb: String,
        pathOriginal: String,
        width: Int,
        height: Int,
        bytesOriginal: Int,
        hash: String,
        blurhash: String? = nil,
        duration: Double? = nil,
        approxBitrateMbps: Double? = nil,
        preset: String? = nil,
        mediaFormat: String? = nil,
        isAnimated: Bool? = nil
    ) {
        self.attachmentID = attachmentID
        self.type = type
        self.index = index
        self.bucketThumb = bucketThumb
        self.bucketOriginal = bucketOriginal
        self.pathThumb = pathThumb
        self.pathOriginal = pathOriginal
        self.width = width
        self.height = height
        self.bytesOriginal = bytesOriginal
        self.hash = hash
        self.blurhash = blurhash
        self.duration = duration
        self.approxBitrateMbps = approxBitrateMbps
        self.preset = preset
        self.mediaFormat = mediaFormat
        self.isAnimated = isAnimated
    }

    // MARK: - Convenience (직렬화 제외)
    var thumbCacheKey: String { "att:\(hash):thumb" }
    var originalCacheKey: String { "att:\(hash):original" }
    var normalizedThumbPath: String { Self.normalizedPath(pathThumb) }
    var normalizedOriginalPath: String { Self.normalizedPath(pathOriginal) }
    var thumbResourcePath: String { Self.resourcePath(bucket: bucketThumb, path: normalizedThumbPath) }
    var originalResourcePath: String { Self.resourcePath(bucket: bucketOriginal, path: normalizedOriginalPath) }
    var preferredDisplayPath: String { thumbResourcePath.isEmpty ? originalResourcePath : thumbResourcePath }
    var hasDisplayablePayload: Bool { !preferredDisplayPath.isEmpty }
    var isAnimatedGIF: Bool {
        type == .image &&
        mediaFormat?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "gif" &&
        isAnimated == true
    }

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
        if let attachmentID { dict["attachmentID"] = attachmentID }
        if let bucketThumb { dict["bucketThumb"] = bucketThumb }
        if let bucketOriginal { dict["bucketOriginal"] = bucketOriginal }
        if let mediaFormat { dict["mediaFormat"] = mediaFormat }
        if let isAnimated { dict["animated"] = isAnimated }
        if let b = blurhash { dict["blurhash"] = b }
        if type == .video, let d = duration {
            dict["duration"] = d
        }
        if type == .video, let approxBitrateMbps {
            dict["approxBitrateMbps"] = approxBitrateMbps
        }
        if type == .video, let preset {
            dict["preset"] = preset
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

    private static func normalizedPath(_ path: String) -> String {
        path.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func resourcePath(bucket: String?, path: String) -> String {
        guard !path.isEmpty else { return "" }
        guard let bucket = bucket?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bucket.isEmpty,
              !path.hasPrefix("/") && !path.hasPrefix("file://") else {
            return path
        }
        return "gs://\(bucket)/\(path)"
    }
}
