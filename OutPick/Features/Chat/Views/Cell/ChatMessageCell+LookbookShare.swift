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
        avatarLoader: ((String) async throws -> UIImage?)? = nil
    ) {
        configureLookbookShareMessage(
            message,
            avatarLoader: avatarLoader
        )
    }
}
