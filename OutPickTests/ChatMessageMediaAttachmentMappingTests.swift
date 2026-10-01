//
//  ChatMessageMediaAttachmentMappingTests.swift
//  OutPickTests
//
//  Created by Codex on 8/20/26.
//

import Foundation
import Testing
@testable import OutPick

struct ChatMessageMediaAttachmentMappingTests {
    @Test func directUploadAttachmentPreservesServerRetentionAndGenerationContract() throws {
        let message = try #require(ChatMessage.from([
            "ID": "message-1",
            "seq": 1,
            "roomID": "room-1",
            "senderUID": "user-1",
            "senderNickname": "사용자",
            "msg": "",
            "sentAt": "2026-07-14T00:00:00.000Z",
            "mediaExpiresAt": "2026-07-21T00:00:00.000Z",
            "mediaContractVersion": 3,
            "attachments": [[
                "attachmentID": "attachment-1",
                "type": "image",
                "index": 0,
                "bucketThumb": "outpick-test-chat-media",
                "bucketOriginal": "outpick-test-chat-media",
                "generationThumb": "22",
                "generationOriginal": "21",
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
        #expect(attachment.generationThumb == "22")
        #expect(attachment.generationOriginal == "21")
        #expect(message.sentAt == ISO8601DateFormatter().date(from: "2026-07-14T00:00:00Z"))
        #expect(message.mediaExpiresAt == ISO8601DateFormatter().date(from: "2026-07-21T00:00:00Z"))
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
            "sentAt": "2026-07-14T00:00:00.000Z",
            "mediaExpiresAt": "2026-07-21T00:00:00.000Z",
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

    @Test func mediaIndexEntryResolvesReadyBucketPathsForSettingsGallery() throws {
        let message = try #require(ChatMessage.from([
            "ID": "message-index",
            "seq": 3,
            "roomID": "room-1",
            "senderUID": "user-1",
            "senderNickname": "사용자",
            "sentAt": "2026-07-14T00:00:00.000Z",
            "mediaExpiresAt": "2026-07-21T00:00:00.000Z",
            "attachments": [[
                "type": "video",
                "index": 0,
                "bucketThumb": "outpick-test-chat-media",
                "bucketOriginal": "outpick-test-chat-media",
                "generationThumb": "32",
                "generationOriginal": "31",
                "pathThumb": "rooms/room-1/messages/message-index/thumbnail",
                "pathOriginal": "rooms/room-1/messages/message-index/display",
                "w": 1920,
                "h": 1080,
                "bytesOriginal": 2_048,
                "duration": 3.5,
                "hash": "video-hash"
            ]]
        ]))

        let entry = try #require(ChatRoomMediaIndexEntry.entries(from: message).first)

        #expect(entry.thumbResourcePath ==
            "gs://outpick-test-chat-media/rooms/room-1/messages/message-index/thumbnail")
        #expect(entry.originalResourcePath ==
            "gs://outpick-test-chat-media/rooms/room-1/messages/message-index/display")
        #expect(entry.generationThumb == "32")
        #expect(entry.generationOriginal == "31")
    }
}
