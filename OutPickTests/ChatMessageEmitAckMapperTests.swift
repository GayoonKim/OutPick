//
//  ChatMessageEmitAckMapperTests.swift
//  OutPickTests
//
//  Created by Codex on 6/22/26.
//

import Testing
@testable import OutPick

struct ChatMessageEmitAckMapperTests {
    @Test func noAckStringIsFailure() {
        #expect(ChatMessageEmitAckMapper.isSuccess(["NO ACK"]) == false)
        #expect(ChatMessageEmitAckMapper.isSuccess(["no_ack"]) == false)
        #expect(ChatMessageEmitAckMapper.isSuccess(["timeout"]) == false)
    }

    @Test func emptyAckStaysSuccessForServerCompatibility() {
        #expect(ChatMessageEmitAckMapper.isSuccess([]))
        #expect(ChatMessageEmitAckMapper.isSuccess([""]))
    }

    @Test func successAndDuplicateDictionaryAreSuccess() {
        #expect(ChatMessageEmitAckMapper.isSuccess(ack(["ok": true])))
        #expect(ChatMessageEmitAckMapper.isSuccess(ack(["success": true])))
        #expect(ChatMessageEmitAckMapper.isSuccess(ack(["duplicate": true])))
        #expect(ChatMessageEmitAckMapper.isSuccess(ack(["status": "accepted"])))
    }

    @Test func errorDictionaryIsFailure() {
        #expect(ChatMessageEmitAckMapper.isSuccess(ack(["ok": false])) == false)
        #expect(ChatMessageEmitAckMapper.isSuccess(ack(["success": false])) == false)
        #expect(ChatMessageEmitAckMapper.isSuccess(ack(["status": "failed"])) == false)
        #expect(ChatMessageEmitAckMapper.isSuccess(ack(["status": "NO ACK"])) == false)
        #expect(ChatMessageEmitAckMapper.isSuccess(ack(["error": "room_closed"])) == false)
    }

    @Test func receiptParsesServerIdentitySequenceAndDuplicateStatus() {
        let receipt = ChatMessageEmitAckMapper.receipt(
            from: ack([
                "ok": true,
                "messageID": "server-message",
                "seq": "42",
                "duplicate": true
            ]),
            roomID: "room-1",
            fallbackMessageID: "client-message"
        )

        #expect(receipt == ChatMessageSendReceipt(
            roomID: "room-1",
            messageID: "server-message",
            seq: 42,
            duplicate: true
        ))
    }

    @Test func failedAckDoesNotProduceReceipt() {
        let receipt = ChatMessageEmitAckMapper.receipt(
            from: ack(["ok": false, "error": "room_closed"]),
            roomID: "room-1",
            fallbackMessageID: "client-message"
        )

        #expect(receipt == nil)
    }

    @Test func receiptMergerClearsFailureAndAppliesConfirmedSequenceAndAttachments() {
        let localAttachment = OutPick.Attachment(
            type: .image,
            index: 0,
            pathThumb: "local-thumb",
            pathOriginal: "local-original",
            width: 100,
            height: 80,
            bytesOriginal: 10,
            hash: "local-hash"
        )
        let confirmedAttachment = OutPick.Attachment(
            type: .image,
            index: 0,
            pathThumb: "server-thumb",
            pathOriginal: "server-original",
            width: 100,
            height: 80,
            bytesOriginal: 10,
            hash: "server-hash"
        )
        let message = makeMessage(attachments: [localAttachment], isFailed: true)

        let merged = ChatOutgoingMessageReceiptMerger.merge(
            message: message,
            receipt: ChatMessageSendReceipt(
                roomID: "room-1",
                messageID: "message-1",
                seq: 42,
                duplicate: true
            ),
            confirmedAttachments: [confirmedAttachment]
        )

        #expect(merged?.seq == 42)
        #expect(merged?.isFailed == false)
        #expect(merged?.attachments == [confirmedAttachment])
        #expect(merged?.msg == "message")
    }

    @Test func receiptMergerRejectsDifferentMessageIdentity() {
        let merged = ChatOutgoingMessageReceiptMerger.merge(
            message: makeMessage(),
            receipt: ChatMessageSendReceipt(
                roomID: "room-1",
                messageID: "different-message",
                seq: 42
            )
        )

        #expect(merged == nil)
    }

    private func ack(_ dict: [String: Any]) -> [Any] {
        [dict]
    }

    private func makeMessage(
        attachments: [OutPick.Attachment] = [],
        isFailed: Bool = false
    ) -> ChatMessage {
        ChatMessage(
            ID: "message-1",
            seq: 0,
            roomID: "room-1",
            senderUID: "sender-1",
            senderEmail: nil,
            senderNickname: "sender",
            msg: "message",
            sentAt: .distantPast,
            attachments: attachments,
            replyPreview: nil,
            isFailed: isFailed
        )
    }
}
