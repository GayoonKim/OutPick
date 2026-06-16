//
//  ReplyPreview.swift
//  OutPick
//
//  Created by Codex on 6/16/26.
//

import Foundation

struct ReplyPreview: Codable, Hashable, Sendable {
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
