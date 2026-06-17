//
//  ChatMessage+LookbookShare.swift
//  OutPick
//
//  Created by Codex on 6/17/26.
//

import Foundation

extension LookbookSharedContent {
    var fallbackPreviewText: String {
        switch contentType {
        case .brand:
            return "브랜드를 공유했어요"
        case .season:
            return "시즌을 공유했어요"
        case .post:
            return "포스트를 공유했어요"
        }
    }

    var compactDisplayTitle: String {
        switch contentType {
        case .brand, .season:
            return titleSnapshot
        case .post:
            return subtitleSnapshot ?? titleSnapshot
        }
    }

    var compactDisplaySubtitle: String? {
        switch contentType {
        case .brand, .season:
            return nil
        case .post:
            return nil
        }
    }
}

extension ChatMessage {
    var isLookbookShareMessage: Bool {
        messageType == .lookbookShare
    }

    var lookbookSharePreviewText: String {
        if let text = msg?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }

        return sharedContent?.fallbackPreviewText ?? "공유 메시지"
    }
}
