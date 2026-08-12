//
//  ChatMessageActionPolicy.swift
//  OutPick
//
//  Created by Codex on 6/17/26.
//

import Foundation

enum ChatMessageAction: Equatable, Hashable, Sendable {
    case reply
    case copy
    case delete
    case report
    case block
    case announce
    case removeMember
}

enum ChatMessageServerAction: Equatable, Sendable {
    case delete
    case announce(authorID: String)
}

struct ChatMessageActionPolicy: Equatable, Sendable {
    let canReply: Bool
    let canCopy: Bool
    let canDelete: Bool
    let canReport: Bool
    let canBlock: Bool
    let canAnnounce: Bool
    let canRemoveMember: Bool

    func allows(_ action: ChatMessageAction) -> Bool {
        switch action {
        case .reply:
            canReply
        case .copy:
            canCopy
        case .delete:
            canDelete
        case .report:
            canReport
        case .block:
            canBlock
        case .announce:
            canAnnounce
        case .removeMember:
            canRemoveMember
        }
    }

    static func make(
        for message: ChatMessage,
        currentUserID: String,
        roomCreatorID: String?
    ) -> ChatMessageActionPolicy {
        let isOwner = currentUserID == message.senderUID
        let isAdmin = roomCreatorID == currentUserID
        let canDelete = isOwner || isAdmin
        let canRemoveMember = isAdmin && !isOwner && !message.senderUID.isEmpty

        if message.isLookbookShareMessage {
            return ChatMessageActionPolicy(
                canReply: true,
                canCopy: false,
                canDelete: canDelete,
                canReport: !canDelete,
                canBlock: !isOwner,
                canAnnounce: false,
                canRemoveMember: canRemoveMember
            )
        }

        return ChatMessageActionPolicy(
            canReply: true,
            canCopy: true,
            canDelete: canDelete,
            canReport: !canDelete,
            canBlock: !isOwner,
            canAnnounce: isAdmin,
            canRemoveMember: canRemoveMember
        )
    }
}
