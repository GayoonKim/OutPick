import Foundation

enum ChatMessageRecordMapper {
    static func record(from message: ChatMessage) -> ChatMessageRecord? {
        guard !message.roomID.isEmpty,
              !message.senderUID.isEmpty,
              !message.senderNickname.isEmpty else {
            return nil
        }

        return ChatMessageRecord(
            id: message.ID,
            seq: message.seq,
            roomID: message.roomID,
            senderUID: message.senderUID,
            senderEmail: message.senderEmail,
            senderNickname: message.senderNickname,
            senderAvatarPath: message.senderAvatarPath,
            messageType: message.messageType?.rawValue,
            msg: message.msg,
            sentAt: message.sentAt,
            attachments: encode(message.attachments.sorted { $0.index < $1.index }) ?? "[]",
            sharedContent: message.sharedContent.flatMap(encode),
            isFailed: message.isFailed,
            replyPreview: message.replyPreview.flatMap(encode),
            isDeleted: message.isDeleted
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
            roomID: record.roomID,
            senderUID: record.senderUID,
            senderEmail: record.senderEmail,
            senderNickname: record.senderNickname,
            senderAvatarPath: record.senderAvatarPath,
            messageType: messageType,
            msg: record.msg,
            sentAt: record.sentAt,
            attachments: attachments,
            sharedContent: sharedContent,
            replyPreview: decode(ReplyPreview.self, from: record.replyPreview),
            isFailed: record.isFailed,
            isDeleted: record.isDeleted
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
