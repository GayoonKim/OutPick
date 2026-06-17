//
//  ChatMessageActionPolicy.swift
//  OutPick
//
//  Created by Codex on 6/17/26.
//

import Foundation

struct ChatMessageActionPolicy: Equatable, Sendable {
    let canReply: Bool
    let canCopy: Bool
    let canDelete: Bool
    let canReport: Bool
    let canAnnounce: Bool

    static func make(
        for message: ChatMessage,
        currentUserID: String,
        roomCreatorID: String?
    ) -> ChatMessageActionPolicy {
        let isOwner = currentUserID == message.senderID
        let isAdmin = roomCreatorID == currentUserID
        let canDelete = isOwner || isAdmin

        if message.isLookbookShareMessage {
            return ChatMessageActionPolicy(
                canReply: true,
                canCopy: false,
                canDelete: canDelete,
                canReport: !canDelete,
                canAnnounce: false
            )
        }

        return ChatMessageActionPolicy(
            canReply: true,
            canCopy: true,
            canDelete: canDelete,
            canReport: !canDelete,
            canAnnounce: isAdmin
        )
    }
}
