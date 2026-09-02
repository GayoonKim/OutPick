import Foundation

enum ChatMessageRecordMapper {
    static func record(from message: ChatMessage) -> ChatMessageRecord? {
        let isValidRoleEvent = message.messageType == .roomRoleEvent
            && message.serverGenerated
            && message.roleEvent != nil
        guard !message.roomID.isEmpty else {
            return nil
        }
        if message.messageType == .roomRoleEvent {
            guard isValidRoleEvent else { return nil }
        } else if !message.isDeleted
                    && (message.senderUID.isEmpty || message.senderNickname.isEmpty) {
            return nil
        }

        return ChatMessageRecord(
            id: message.ID,
            seq: message.seq,
            unreadMessageSeq: message.effectiveUnreadMessageSeq,
            roomID: message.roomID,
            senderUID: message.senderUID.isEmpty ? nil : message.senderUID,
            senderNickname: message.senderNickname.isEmpty ? nil : message.senderNickname,
            senderAvatarPath: message.senderAvatarPath,
            messageType: message.isDeleted ? nil : message.messageType?.rawValue,
            roleEvent: message.isDeleted ? nil : message.roleEvent.flatMap(encode),
            msg: message.isDeleted ? nil : message.msg,
            sentAt: message.sentAt,
            attachments: message.isDeleted ? "[]" : (encode(message.attachments.sorted { $0.index < $1.index }) ?? "[]"),
            sharedContent: message.isDeleted ? nil : message.sharedContent.flatMap(encode),
            isFailed: message.isDeleted ? false : message.isFailed,
            replyPreview: message.replyPreview.flatMap(encode),
            isDeleted: message.isDeleted,
            deletionRevision: message.deletionRevision,
            deletedAt: message.deletedAt
        )
    }

    static func message(from record: ChatMessageRecord) throws -> ChatMessage {
        let attachments = try JSONDecoder().decode([Attachment].self, from: Data(record.attachments.utf8))
        let messageType = ChatMessageType(legacyRawValue: record.messageType)
        let sharedContent: LookbookSharedContent? = messageType == .lookbookShare
            ? decode(LookbookSharedContent.self, from: record.sharedContent)
            : nil

        return ChatMessage(
            ID: record.id,
            seq: record.seq,
            unreadMessageSeq: record.unreadMessageSeq,
            roomID: record.roomID,
            senderUID: record.senderUID ?? "",
            senderNickname: record.senderNickname ?? "",
            senderAvatarPath: record.senderAvatarPath,
            messageType: messageType,
            serverGenerated: messageType == .roomRoleEvent,
            roleEvent: decode(RoomRoleEventPayload.self, from: record.roleEvent),
            msg: record.msg,
            sentAt: record.sentAt,
            attachments: attachments,
            sharedContent: sharedContent,
            replyPreview: decode(ReplyPreview.self, from: record.replyPreview),
            isFailed: record.isFailed,
            isDeleted: record.isDeleted,
            deletionRevision: record.deletionRevision,
            deletedAt: record.deletedAt
        )
    }

    static func decode<T: Decodable>(_ type: T.Type, from json: String?) -> T? {
        guard let json else { return nil }
        return try? JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private static func encode<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
