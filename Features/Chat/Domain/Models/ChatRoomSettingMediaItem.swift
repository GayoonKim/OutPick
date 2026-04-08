//
//  ChatRoomSettingMediaItem.swift
//  OutPick
//
//  Created by Codex on 3/7/26.
//

import Foundation

struct ChatRoomSettingMediaItem: Hashable {
    let messageID: String
    let idx: Int
    let hash: String?
    let thumbKey: String?
    let originalKey: String?
    let thumbURL: String?
    let originalURL: String?
    let localThumb: String?
    let sentAt: Date
    let isVideo: Bool

    var id: String {
        "\(messageID)#\(idx)"
    }

    var cursor: ChatRoomMediaIndexCursor {
        ChatRoomMediaIndexCursor(sentAt: sentAt, messageID: messageID, idx: idx)
    }

    var storagePath: String? {
        if let originalURL, !originalURL.isEmpty {
            return originalURL
        }
        if let thumbURL, !thumbURL.isEmpty {
            return thumbURL
        }
        return nil
    }

    var thumbnailPath: String? {
        if let localThumb, !localThumb.isEmpty {
            return localThumb
        }
        if let thumbURL, !thumbURL.isEmpty {
            return thumbURL
        }
        if let originalURL, !originalURL.isEmpty {
            return originalURL
        }
        return nil
    }

    var originalPath: String? {
        if let originalURL, !originalURL.isEmpty {
            return originalURL
        }
        if let thumbURL, !thumbURL.isEmpty {
            return thumbURL
        }
        if let localThumb, !localThumb.isEmpty {
            return localThumb
        }
        return nil
    }

    var videoPath: String? {
        guard isVideo else { return nil }
        return originalPath
    }

    var dedupeKeys: Set<String> {
        let mediaKind = isVideo ? "video" : "image"
        var keys = Set<String>()

        if let hash, !hash.isEmpty {
            keys.insert("\(mediaKind)#hash:\(hash)")
        }

        for key in [thumbKey, originalKey] {
            guard let key, !key.isEmpty else { continue }
            keys.insert("\(mediaKind)#key:\(key)")
        }

        for path in [localThumb, thumbURL, originalURL] {
            guard let canonical = Self.canonicalPath(path) else { continue }
            keys.insert("\(mediaKind)#path:\(canonical)")
        }

        return keys
    }

    var previewPaths: [String] {
        var seen = Set<String>()
        return [localThumb, thumbURL, originalURL].compactMap { path in
            guard let path, !path.isEmpty else { return nil }
            guard seen.insert(path).inserted else { return nil }
            return path
        }
    }

    private static func canonicalPath(_ path: String?) -> String? {
        guard let rawPath = path?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.isEmpty else { return nil }

        if rawPath.hasPrefix("file://"),
           let url = URL(string: rawPath),
           url.isFileURL {
            return url.standardizedFileURL.path
        }

        if rawPath.hasPrefix("/") {
            return URL(fileURLWithPath: rawPath).standardizedFileURL.path
        }

        return rawPath
    }
}
