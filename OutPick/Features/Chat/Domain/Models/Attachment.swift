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
    var normalizedThumbPath: String { Self.normalizedPath(pathThumb) }
    var normalizedOriginalPath: String { Self.normalizedPath(pathOriginal) }
    var preferredDisplayPath: String { normalizedThumbPath.isEmpty ? normalizedOriginalPath : normalizedThumbPath }
    var hasDisplayablePayload: Bool { !preferredDisplayPath.isEmpty }

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

    private static func normalizedPath(_ path: String) -> String {
        path.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
