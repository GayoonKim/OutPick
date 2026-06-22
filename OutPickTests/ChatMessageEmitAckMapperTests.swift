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

    private func ack(_ dict: [String: Any]) -> [Any] {
        [dict]
    }
}
