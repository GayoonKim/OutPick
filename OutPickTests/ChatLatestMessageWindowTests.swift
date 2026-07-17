//
//  ChatLatestMessageWindowTests.swift
//  OutPickTests
//
//  Created by Codex on 7/17/26.
//

import Foundation
import Testing
@testable import OutPick

struct ChatLatestMessageWindowTests {
    @Test func normalTargetUsesExclusiveBeforeSeqWithFixedLimit() throws {
        let query = try ChatLatestMessageWindow.query(for: 10_010)

        #expect(query == .beforeSeq(10_011, limit: 80))
    }

    @Test func maxTargetUsesOverflowSafeLatestQuery() throws {
        let query = try ChatLatestMessageWindow.query(for: Int64.max)

        #expect(query == .latest(limit: 80))
    }

    @Test func windowFiltersFutureAndInvalidSeqDeduplicatesSortsAndBounds() throws {
        var fetched = (1...90).map { makeMessage(id: "message-\($0)", seq: Int64($0)) }
        fetched.append(makeMessage(id: "message-90", seq: 90))
        fetched.append(makeMessage(id: "future", seq: 91))
        fetched.append(makeMessage(id: "invalid", seq: 0))

        let window = try ChatLatestMessageWindow.make(targetSeq: 90, fetched: Array(fetched.reversed()))

        #expect(window.messages.count == 80)
        #expect(window.messages.first?.seq == 11)
        #expect(window.messages.last?.seq == 90)
        #expect(window.messages.map(\.seq) == Array(Int64(11)...Int64(90)))
    }

    @Test func invalidOrMissingTargetFailsClosed() {
        #expect(throws: ChatLatestMessageWindowError.invalidTarget) {
            try ChatLatestMessageWindow.query(for: 0)
        }
        #expect(throws: ChatLatestMessageWindowError.targetMissing) {
            try ChatLatestMessageWindow.make(
                targetSeq: 10,
                fetched: [makeMessage(id: "message-9", seq: 9)]
            )
        }
    }

    private func makeMessage(id: String, seq: Int64) -> ChatMessage {
        ChatMessage(
            ID: id,
            seq: seq,
            roomID: "room-1",
            senderUID: "sender-1",
            senderEmail: nil,
            senderNickname: "sender",
            senderAvatarPath: nil,
            msg: id,
            sentAt: Date(timeIntervalSince1970: TimeInterval(seq)),
            attachments: [],
            replyPreview: nil
        )
    }
}
