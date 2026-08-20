//
//  ChatMessageMediaAttachmentMappingTests.swift
//  OutPickTests
//
//  Created by Codex on 8/20/26.
//

import Testing
@testable import OutPick

struct ChatMessageMediaAttachmentMappingTests {
    @Test func v2AttachmentPreservesReadyBucketContract() throws {
        let message = try #require(ChatMessage.from([
            "ID": "message-1",
            "seq": 1,
            "roomID": "room-1",
            "senderUID": "user-1",
            "senderNickname": "사용자",
            "msg": "",
            "attachments": [[
                "attachmentID": "attachment-1",
                "type": "image",
                "index": 0,
                "bucketThumb": "outpick-test-chat-media",
                "bucketOriginal": "outpick-test-chat-media",
                "pathThumb": "rooms/room-1/messages/message-1/attachments/attachment-1/thumbnail",
                "pathOriginal": "rooms/room-1/messages/message-1/attachments/attachment-1/display",
                "w": 588,
                "h": 399,
                "bytesOriginal": 12_160,
                "hash": "content-hash",
                "mediaFormat": "jpeg",
                "animated": false
            ]]
        ]))

        let attachment = try #require(message.attachments.first)
        #expect(attachment.attachmentID == "attachment-1")
        #expect(attachment.bucketThumb == "outpick-test-chat-media")
        #expect(attachment.bucketOriginal == "outpick-test-chat-media")
        #expect(attachment.mediaFormat == "jpeg")
        #expect(attachment.isAnimated == false)
        #expect(attachment.thumbResourcePath ==
            "gs://outpick-test-chat-media/rooms/room-1/messages/message-1/attachments/attachment-1/thumbnail")
        #expect(attachment.originalResourcePath ==
            "gs://outpick-test-chat-media/rooms/room-1/messages/message-1/attachments/attachment-1/display")
    }

    @Test func animatedGIFMetadataDrivesConfirmedGIFPresentation() throws {
        let message = try #require(ChatMessage.from([
            "ID": "message-gif",
            "seq": 2,
            "roomID": "room-1",
            "senderUID": "user-1",
            "senderNickname": "사용자",
            "msg": "",
            "attachments": [[
                "attachmentID": "attachment-gif",
                "type": "image",
                "index": 0,
                "pathThumb": "thumbnail",
                "pathOriginal": "display",
                "w": 800,
                "h": 800,
                "bytesOriginal": 3_959,
                "hash": "",
                "mediaFormat": "gif",
                "animated": true
            ]]
        ]))

        let attachment = try #require(message.attachments.first)
        #expect(attachment.mediaFormat == "gif")
        #expect(attachment.isAnimated == true)
        #expect(attachment.isAnimatedGIF)
    }
}
