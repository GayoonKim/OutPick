//
//  ChatMessageLookbookShareTests.swift
//  OutPickTests
//
//  Created by Codex on 6/16/26.
//

import Foundation
import Testing
@testable import OutPick

struct ChatMessageLookbookShareTests {
    @Test func legacyMessageTypesNormalizeWithoutBreakingMessages() throws {
        let textMessage = try #require(ChatMessage.from(basePayload(messageType: "Text", msg: "안녕")))
        #expect(textMessage.messageType == .text)
        #expect(textMessage.msg == "안녕")
        #expect(textMessage.sharedContent == nil)

        let imageMessage = try #require(ChatMessage.from(basePayload(
            messageType: "Image",
            msg: "",
            attachments: [[
                "type": "image",
                "pathThumb": "rooms/room-1/messages/image/thumb.jpg",
                "pathOriginal": "rooms/room-1/messages/image/original.jpg"
            ]]
        )))
        #expect(imageMessage.messageType == .image)
        #expect(imageMessage.attachments.first?.type == .image)

        let videoMessage = try #require(ChatMessage.from(basePayload(
            messageType: "Video",
            msg: "",
            attachments: [[
                "type": "video",
                "pathThumb": "rooms/room-1/messages/video/thumb.jpg",
                "pathOriginal": "rooms/room-1/messages/video/video.mp4",
                "duration": 12.5
            ]]
        )))
        #expect(videoMessage.messageType == .video)
        #expect(videoMessage.attachments.first?.type == .video)

        let nilTypeMessage = try #require(ChatMessage.from(basePayload(messageType: nil, msg: "legacy")))
        #expect(nilTypeMessage.messageType == nil)
        #expect(nilTypeMessage.msg == "legacy")
    }

    @Test func validLookbookShareDecodesAndSerializesSharedContent() throws {
        let payload = basePayload(
            messageType: "lookbookShare",
            msg: "이 시즌 봐봐",
            sharedContent: [
                "schemaVersion": 1,
                "contentType": "season",
                "brandID": "brand-1",
                "seasonID": "season-1",
                "titleSnapshot": "2026 Summer",
                "subtitleSnapshot": "HATCHINGROOM",
                "thumbnailPathSnapshot": "lookbook/brand-1/season-1/thumb.jpg"
            ]
        )

        let message = try #require(ChatMessage.from(payload))
        #expect(message.messageType == .lookbookShare)
        #expect(message.sharedContent?.contentType == .season)
        #expect(message.sharedContent?.brandID == "brand-1")
        #expect(message.sharedContent?.seasonID == "season-1")
        #expect(message.sharedContent?.titleSnapshot == "2026 Summer")

        let firestoreDict = message.toDict()
        #expect(firestoreDict["messageType"] as? String == "lookbookShare")
        #expect(firestoreDict["msg"] as? String == "이 시즌 봐봐")
        let firestoreSharedContent = try #require(firestoreDict["sharedContent"] as? [String: Any])
        #expect(firestoreSharedContent["contentType"] as? String == "season")
        #expect(firestoreSharedContent["seasonID"] as? String == "season-1")

        let socketDict = try #require(message.toSocketRepresentation() as? [String: Any])
        #expect(socketDict["messageType"] as? String == "lookbookShare")
        let socketSharedContent = try #require(socketDict["sharedContent"] as? [String: Any])
        #expect(socketSharedContent["brandID"] as? String == "brand-1")
    }

    @Test func invalidLookbookShareKeepsMessageAndDropsSharedContent() throws {
        let payload = basePayload(
            messageType: "lookbookShare",
            msg: "이 포스트 어때",
            sharedContent: [
                "schemaVersion": 1,
                "contentType": "post",
                "brandID": "brand-1",
                "postID": "post-1",
                "titleSnapshot": "포스트"
            ]
        )

        let message = try #require(ChatMessage.from(payload))
        #expect(message.messageType == .lookbookShare)
        #expect(message.msg == "이 포스트 어때")
        #expect(message.sharedContent == nil)
    }

    @Test func codableDecodeTreatsUnknownMessageTypeAsNil() throws {
        let json = """
        {
          "ID": "message-1",
          "seq": 1,
          "roomID": "room-1",
          "senderID": "sender@example.com",
          "senderNickname": "sender",
          "messageType": "Sticker",
          "msg": "스티커",
          "attachments": []
        }
        """

        let message = try JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
        #expect(message.messageType == nil)
        #expect(message.msg == "스티커")
    }

    @Test func codableDecodeDropsInvalidSharedContentWithoutDroppingMessage() throws {
        let json = """
        {
          "ID": "message-1",
          "seq": 1,
          "roomID": "room-1",
          "senderID": "sender@example.com",
          "senderNickname": "sender",
          "messageType": "lookbookShare",
          "msg": "이 시즌 봐봐",
          "attachments": [],
          "sharedContent": {
            "schemaVersion": 1,
            "contentType": "season",
            "brandID": "brand-1",
            "seasonID": "season-1",
            "titleSnapshot": ""
          }
        }
        """

        let message = try JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
        #expect(message.messageType == .lookbookShare)
        #expect(message.sharedContent == nil)
        #expect(message.msg == "이 시즌 봐봐")
    }

    private func basePayload(
        messageType: String?,
        msg: String,
        attachments: [[String: Any]] = [],
        sharedContent: [String: Any]? = nil
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "ID": "message-1",
            "seq": 1,
            "roomID": "room-1",
            "senderID": "sender@example.com",
            "senderNickname": "sender",
            "msg": msg,
            "sentAt": "2026-06-16T00:00:00.000Z",
            "attachments": attachments
        ]
        if let messageType {
            payload["messageType"] = messageType
        }
        if let sharedContent {
            payload["sharedContent"] = sharedContent
        }
        return payload
    }
}
