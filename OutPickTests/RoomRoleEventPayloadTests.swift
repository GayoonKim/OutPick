import Foundation
import Testing
@testable import OutPick

struct RoomRoleEventPayloadTests {
    @Test func codableRoundTripPreservesIndependentUnreadSequence() throws {
        var message = makeMessage(id: "message-9", seq: 9, type: .text)
        message.unreadMessageSeq = 4
        let restored = try JSONDecoder().decode(
            ChatMessage.self, from: JSONEncoder().encode(message)
        )

        #expect(restored.seq == 9)
        #expect(restored.unreadMessageSeq == 4)
        #expect(restored.effectiveUnreadMessageSeq == 4)
    }

    @Test func codableLegacyMessageFallsBackToTimelineSequence() throws {
        let message = makeMessage(id: "legacy-9", seq: 9, type: .text)
        let restored = try JSONDecoder().decode(
            ChatMessage.self, from: JSONEncoder().encode(message)
        )

        #expect(restored.unreadMessageSeq == 9)
        #expect(restored.effectiveUnreadMessageSeq == 9)
    }

    @Test func codableRoleEventDoesNotRestoreUnreadSequence() throws {
        var message = makeMessage(id: "role-9", seq: 9, type: .roomRoleEvent)
        message.unreadMessageSeq = 4
        let restored = try JSONDecoder().decode(
            ChatMessage.self, from: JSONEncoder().encode(message)
        )

        #expect(restored.unreadMessageSeq == nil)
        #expect(restored.effectiveUnreadMessageSeq == nil)
        #expect(restored.roleEvent == message.roleEvent)
    }

    @Test func dictionaryMessageMappingAcceptsConfirmedServerContract() throws {
        let message = try #require(ChatMessage.from([
            "ID": "event-1",
            "roomID": "room-1",
            "seq": 4,
            "messageType": "roomRoleEvent",
            "serverGenerated": true,
            "sentAt": "2026-09-01T00:00:00Z",
            "roleEvent": [
                "kind": "ownershipTransferred",
                "subjectUID": "user-1",
                "subjectNicknameSnapshot": "사용자"
            ]
        ]))

        #expect(message.senderUID.isEmpty)
        #expect(message.messageType == .roomRoleEvent)
        #expect(message.serverGenerated)
        #expect(message.roleEvent?.kind == .ownershipTransferred)
        #expect(message.roleEvent?.subjectUID == "user-1")
    }

    @Test func anonymizedRoleEventOmitsSubjectUIDWhenEncoded() throws {
        let payload = RoomRoleEventPayload(
            kind: .moderatorResigned,
            subjectUID: nil,
            subjectNicknameSnapshot: "알 수 없는 사용자"
        )
        let message = ChatMessage(
            ID: "event-2",
            seq: 5,
            roomID: "room-1",
            senderUID: "",
            senderNickname: "",
            messageType: .roomRoleEvent,
            serverGenerated: true,
            roleEvent: payload,
            msg: nil,
            sentAt: nil,
            attachments: []
        )

        let roleEvent = try #require(message.toDict()["roleEvent"] as? [String: Any])
        #expect(roleEvent["subjectUID"] == nil)
        #expect(roleEvent["subjectNicknameSnapshot"] as? String == "알 수 없는 사용자")
    }

    @Test func senderlessRoleEventWithoutServerMarkerIsRejected() {
        #expect(ChatMessage.from([
            "ID": "event-3",
            "roomID": "room-1",
            "messageType": "roomRoleEvent",
            "roleEvent": [
                "kind": "moderatorRevoked",
                "subjectNicknameSnapshot": "사용자"
            ]
        ]) == nil)
    }

    @Test func forgedSenderCannotReplaceServerMarker() {
        #expect(ChatMessage.from([
            "ID": "event-4",
            "roomID": "room-1",
            "senderUID": "forged-user",
            "senderNickname": "Forged User",
            "messageType": "roomRoleEvent",
            "roleEvent": [
                "kind": "moderatorAssigned",
                "subjectNicknameSnapshot": "사용자"
            ]
        ]) == nil)
    }

    @Test func displayTextUsesRoleKindAndNicknameSnapshot() {
        let nickname = "사용자"
        #expect(RoomRoleEventPayload(
            kind: .moderatorAssigned,
            subjectUID: "user-1",
            subjectNicknameSnapshot: nickname
        ).displayText == "사용자님이 관리자로 지정되었어요")
        #expect(RoomRoleEventPayload(
            kind: .moderatorRevoked,
            subjectUID: "user-1",
            subjectNicknameSnapshot: nickname
        ).displayText == "사용자님의 관리자 권한이 해제되었어요")
        #expect(RoomRoleEventPayload(
            kind: .moderatorResigned,
            subjectUID: "user-1",
            subjectNicknameSnapshot: nickname
        ).displayText == "사용자님이 관리자에서 물러났어요")
        #expect(RoomRoleEventPayload(
            kind: .ownershipTransferred,
            subjectUID: "user-1",
            subjectNicknameSnapshot: nickname
        ).displayText == "사용자님이 방장이 되었어요")
    }

    @Test func roomListPreviewExcludesRoleEventsAndPreservesMessageOrder() {
        let newestRoleEvent = makeMessage(id: "role-newest", seq: 6, type: .roomRoleEvent)
        let nextRoleEvent = makeMessage(id: "role-next", seq: 5, type: .roomRoleEvent)
        let newestMessage = makeMessage(id: "message-4", seq: 4, type: .text)
        let middleMessage = makeMessage(id: "message-3", seq: 3, type: .text)
        let oldestMessage = makeMessage(id: "message-2", seq: 2, type: .text)

        let result = FirebaseChatRoomRepository.eligiblePreviewMessages(
            fromNewestFirst: [
                newestRoleEvent,
                nextRoleEvent,
                newestMessage,
                middleMessage,
                oldestMessage
            ],
            limit: 3
        )

        let containsRoleEvent = result.contains { !$0.isEligibleForRoomListPreview }
        #expect(result.map(\.ID) == ["message-2", "message-3", "message-4"])
        #expect(!containsRoleEvent)
    }

    private func makeMessage(id: String, seq: Int64, type: ChatMessageType) -> ChatMessage {
        ChatMessage(
            ID: id,
            seq: seq,
            roomID: "room-1",
            senderUID: type == .roomRoleEvent ? "" : "user-1",
            senderNickname: type == .roomRoleEvent ? "" : "사용자",
            messageType: type,
            serverGenerated: type == .roomRoleEvent,
            roleEvent: type == .roomRoleEvent
                ? RoomRoleEventPayload(
                    kind: .moderatorAssigned,
                    subjectUID: "user-2",
                    subjectNicknameSnapshot: "관리자"
                )
                : nil,
            msg: type == .text ? id : nil,
            sentAt: Date(timeIntervalSince1970: TimeInterval(seq)),
            attachments: []
        )
    }
}
