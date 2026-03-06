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

    var previewPaths: [String] {
        var seen = Set<String>()
        return [localThumb, thumbURL, originalURL].compactMap { path in
            guard let path, !path.isEmpty else { return nil }
            guard seen.insert(path).inserted else { return nil }
            return path
        }
    }
}
