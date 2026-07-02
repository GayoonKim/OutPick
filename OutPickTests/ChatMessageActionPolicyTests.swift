//
//  ChatMessageActionPolicyTests.swift
//  OutPickTests
//
//  Created by Codex on 6/17/26.
//

import Foundation
import Testing
@testable import OutPick

struct ChatMessageActionPolicyTests {
    @Test func lookbookShareAllowsReplyButBlocksCopyAndAnnounce() {
        let message = makeMessage(
            senderUID: "sender@example.com",
            messageType: .lookbookShare,
            msg: "브랜드를 공유했어요",
            sharedContent: makeSharedContent()
        )

        let policy = ChatMessageActionPolicy.make(
            for: message,
            currentUserID: "viewer@example.com",
            roomCreatorID: "admin@example.com"
        )

        #expect(policy.canReply)
        #expect(policy.canCopy == false)
        #expect(policy.canAnnounce == false)
        #expect(policy.canDelete == false)
        #expect(policy.canReport)
    }

    @Test func lookbookShareKeepsDeletePermissionForOwnerOrAdmin() {
        let message = makeMessage(
            senderUID: "sender@example.com",
            messageType: .lookbookShare,
            msg: nil,
            sharedContent: makeSharedContent()
        )

        let ownerPolicy = ChatMessageActionPolicy.make(
            for: message,
            currentUserID: "sender@example.com",
            roomCreatorID: "admin@example.com"
        )
        #expect(ownerPolicy.canDelete)
        #expect(ownerPolicy.canReport == false)

        let adminPolicy = ChatMessageActionPolicy.make(
            for: message,
            currentUserID: "admin@example.com",
            roomCreatorID: "admin@example.com"
        )
        #expect(adminPolicy.canDelete)
        #expect(adminPolicy.canReport == false)
        #expect(adminPolicy.canAnnounce == false)
    }

    @Test func regularMessageKeepsExistingCopyAndAdminAnnouncementPolicy() {
        let message = makeMessage(
            senderUID: "sender@example.com",
            messageType: .text,
            msg: "안녕",
            sharedContent: nil
        )

        let policy = ChatMessageActionPolicy.make(
            for: message,
            currentUserID: "admin@example.com",
            roomCreatorID: "admin@example.com"
        )

        #expect(policy.canReply)
        #expect(policy.canCopy)
        #expect(policy.canDelete)
        #expect(policy.canReport == false)
        #expect(policy.canAnnounce)
    }

    @Test func lookbookSharePreviewUsesMessageTextThenFallback() {
        let content = makeSharedContent(contentType: .post)
        let messageWithText = makeMessage(
            senderUID: "sender@example.com",
            messageType: .lookbookShare,
            msg: "이 포스트 봐봐",
            sharedContent: content
        )
        #expect(messageWithText.lookbookSharePreviewText == "이 포스트 봐봐")

        let messageWithoutText = makeMessage(
            senderUID: "sender@example.com",
            messageType: .lookbookShare,
            msg: "   ",
            sharedContent: content
        )
        #expect(messageWithoutText.lookbookSharePreviewText == "포스트를 공유했어요")

        let invalidSnapshotMessage = makeMessage(
            senderUID: "sender@example.com",
            messageType: .lookbookShare,
            msg: nil,
            sharedContent: nil
        )
        #expect(invalidSnapshotMessage.lookbookSharePreviewText == "공유 메시지")
    }

    private func makeMessage(
        senderUID: String,
        messageType: ChatMessageType?,
        msg: String?,
        sharedContent: LookbookSharedContent?
    ) -> ChatMessage {
        ChatMessage(
            ID: "message-1",
            seq: 1,
            roomID: "room-1",
            senderUID: senderUID,
            senderEmail: nil,
            senderNickname: "sender",
            senderAvatarPath: nil,
            messageType: messageType,
            msg: msg,
            sentAt: Date(timeIntervalSince1970: 0),
            attachments: [],
            sharedContent: sharedContent,
            replyPreview: nil,
            isFailed: false,
            isDeleted: false
        )
    }

    private func makeSharedContent(
        contentType: LookbookSharedContent.ContentType = .brand
    ) -> LookbookSharedContent {
        LookbookSharedContent(
            schemaVersion: 1,
            contentType: contentType,
            brandID: "brand-1",
            seasonID: contentType == .brand ? nil : "season-1",
            postID: contentType == .post ? "post-1" : nil,
            titleSnapshot: "공유 제목",
            subtitleSnapshot: "공유 설명",
            thumbnailPathSnapshot: "lookbook/thumb.jpg"
        )
    }
}
