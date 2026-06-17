//
//  ChatMessageCell+LookbookShare.swift
//  OutPick
//
//  Created by Codex on 6/17/26.
//

import UIKit

extension ChatMessageCell {
    func configureWithLookbookShare(
        with message: ChatMessage,
        thumbnailLoader: ((String) async -> UIImage?)? = nil,
        avatarLoader: ((String) async -> UIImage?)? = nil
    ) {
        configureLookbookShareMessage(
            message,
            thumbnailLoader: thumbnailLoader,
            avatarLoader: avatarLoader
        )
    }
}
