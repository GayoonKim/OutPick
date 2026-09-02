import Foundation
import Testing
@testable import OutPick

struct ChatMessageRecordMapperTests {
    @Test func messageRecordRoundTripSortsAttachments() throws {
        let second = Attachment(type: .image, index: 2, pathThumb: "t2", pathOriginal: "o2", width: 2, height: 2, bytesOriginal: 2, hash: "h2", blurhash: nil, duration: nil)
        let first = Attachment(type: .image, index: 1, pathThumb: "t1", pathOriginal: "o1", width: 1, height: 1, bytesOriginal: 1, hash: "h1", blurhash: nil, duration: nil)
        let message = GRDBTestFixtures.message(attachments: [second, first])

        let record = try #require(ChatMessageRecordMapper.record(from: message))
        let restored = try ChatMessageRecordMapper.message(from: record)

        #expect(restored.ID == message.ID)
        #expect(restored.unreadMessageSeq == message.seq)
        #expect(restored.attachments.map(\.index) == [1, 2])
    }

    @Test func invalidRequiredIdentifiersAreSkipped() {
        let invalid = GRDBTestFixtures.message(roomID: "")
        #expect(ChatMessageRecordMapper.record(from: invalid) == nil)
    }

    @Test func senderlessServerRoleEventRoundTripPreservesStructuredPayload() throws {
        let payload = RoomRoleEventPayload(
            kind: .moderatorAssigned,
            subjectUID: "user-1",
            subjectNicknameSnapshot: "사용자"
        )
        let message = ChatMessage(
            ID: "role-event-1",
            seq: 13,
            roomID: "room-1",
            senderUID: "",
            senderNickname: "",
            messageType: .roomRoleEvent,
            serverGenerated: true,
            roleEvent: payload,
            msg: nil,
            sentAt: Date(timeIntervalSince1970: 300),
            attachments: []
        )

        let record = try #require(ChatMessageRecordMapper.record(from: message))
        let restored = try ChatMessageRecordMapper.message(from: record)

        #expect(record.roleEvent != nil)
        #expect(restored.messageType == .roomRoleEvent)
        #expect(restored.serverGenerated)
        #expect(restored.roleEvent == payload)
        #expect(restored.unreadMessageSeq == nil)
        #expect(restored.senderUID.isEmpty)
    }

    @Test func clientShapedRoleEventIsRejectedFromLocalPersistence() {
        let message = ChatMessage(
            ID: "invalid-role-event",
            seq: 14,
            roomID: "room-1",
            senderUID: "forged-user",
            senderNickname: "Forged User",
            messageType: .roomRoleEvent,
            serverGenerated: false,
            roleEvent: RoomRoleEventPayload(
                kind: .moderatorAssigned,
                subjectUID: "user-1",
                subjectNicknameSnapshot: "사용자"
            ),
            msg: nil,
            sentAt: nil,
            attachments: []
        )

        #expect(ChatMessageRecordMapper.record(from: message) == nil)
    }

    @Test func regularDeletionRoundTripKeepsPresentationAndScrubsContent() throws {
        let sentAt = Date(timeIntervalSince1970: 100)
        let replyPreview = ReplyPreview(
            messageID: "source",
            sender: "Earlier User",
            text: "이전 메시지"
        )
        let message = ChatMessage(
            ID: "deleted",
            seq: 10,
            roomID: "room-1",
            senderUID: "user-1",
            senderNickname: "User",
            senderAvatarPath: "profiles/user-1/avatar",
            messageType: .text,
            msg: "삭제 전 원문",
            sentAt: sentAt,
            attachments: [Attachment(
                type: .image,
                index: 0,
                pathThumb: "thumb/path",
                pathOriginal: "original/path",
                width: 10,
                height: 10,
                bytesOriginal: 10,
                hash: "hash"
            )],
            replyPreview: replyPreview,
            isDeleted: true,
            deletionRevision: 2,
            deletedAt: Date(timeIntervalSince1970: 200)
        )

        let record = try #require(ChatMessageRecordMapper.record(from: message))
        let restored = try ChatMessageRecordMapper.message(from: record)

        #expect(restored.senderUID == message.senderUID)
        #expect(restored.senderNickname == message.senderNickname)
        #expect(restored.senderAvatarPath == message.senderAvatarPath)
        #expect(restored.sentAt == sentAt)
        #expect(restored.replyPreview == replyPreview)
        #expect(restored.msg == nil)
        #expect(restored.attachments.isEmpty)
        #expect(restored.sharedContent == nil)
        #expect(restored.isDeleted)
    }

    @Test func accountDeletionRoundTripKeepsAnonymousPresentationAndTime() throws {
        let sentAt = Date(timeIntervalSince1970: 100)
        let message = ChatMessage(
            ID: "anonymized",
            seq: 11,
            roomID: "room-1",
            senderUID: "",
            senderNickname: "알 수 없는 사용자",
            senderAvatarPath: nil,
            messageType: nil,
            msg: nil,
            sentAt: sentAt,
            attachments: [],
            replyPreview: nil,
            isDeleted: true,
            deletionRevision: 3,
            deletedAt: Date(timeIntervalSince1970: 200)
        )

        let record = try #require(ChatMessageRecordMapper.record(from: message))
        let restored = try ChatMessageRecordMapper.message(from: record)

        #expect(restored.senderUID.isEmpty)
        #expect(restored.senderNickname == "알 수 없는 사용자")
        #expect(restored.senderAvatarPath == nil)
        #expect(restored.sentAt == sentAt)
        #expect(restored.replyPreview == nil)
        #expect(restored.isDeleted)
    }
}
