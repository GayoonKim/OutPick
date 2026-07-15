import Foundation

struct ChatMessageSendReceipt: Equatable, Sendable {
    let roomID: String
    let messageID: String
    let seq: Int64?
    let duplicate: Bool

    init(
        roomID: String,
        messageID: String,
        seq: Int64?,
        duplicate: Bool = false
    ) {
        self.roomID = roomID
        self.messageID = messageID
        self.seq = seq
        self.duplicate = duplicate
    }
}

enum ChatOutgoingMessageReceiptMerger {
    static func merge(
        message: ChatMessage,
        receipt: ChatMessageSendReceipt,
        confirmedAttachments: [Attachment]? = nil
    ) -> ChatMessage? {
        guard message.ID == receipt.messageID, message.roomID == receipt.roomID else {
            return nil
        }

        let resolvedSeq = receipt.seq.flatMap { $0 > 0 ? $0 : nil } ?? message.seq
        let resolvedAttachments: [Attachment]
        if let confirmedAttachments, confirmedAttachments.isEmpty == false {
            resolvedAttachments = confirmedAttachments
        } else {
            resolvedAttachments = message.attachments
        }

        return ChatMessage(
            ID: message.ID,
            seq: resolvedSeq,
            roomID: message.roomID,
            senderUID: message.senderUID,
            senderEmail: message.senderEmail,
            senderNickname: message.senderNickname,
            senderAvatarPath: message.senderAvatarPath,
            messageType: message.messageType,
            msg: message.msg,
            sentAt: message.sentAt,
            attachments: resolvedAttachments,
            sharedContent: message.sharedContent,
            replyPreview: message.replyPreview,
            isFailed: false,
            isDeleted: message.isDeleted
        )
    }
}
