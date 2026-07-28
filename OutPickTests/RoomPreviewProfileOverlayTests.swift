import Foundation
import Testing
@testable import OutPick

struct RoomPreviewProfileOverlayTests {
    @Test
    func oldAndNewMessagesUseTheSameCurrentPublicProfileWithoutMutatingSnapshots() {
        let oldMessage = makeMessage(
            id: "old",
            nickname: "변경 전",
            avatarPath: "avatars/old.jpg"
        )
        let newMessage = makeMessage(
            id: "new",
            nickname: "변경 후 snapshot",
            avatarPath: "avatars/intermediate.jpg"
        )
        let profile = LocalChatUser(
            userID: "user-1",
            nickname: "현재 닉네임",
            profileImagePath: "avatars/current.jpg"
        )

        let resolved = RoomPreviewProfileOverlay.apply(
            to: [oldMessage, newMessage],
            profileForUserID: { $0 == "user-1" ? profile : nil }
        )

        #expect(resolved.map(\.senderNickname) == ["현재 닉네임", "현재 닉네임"])
        #expect(resolved.map(\.senderAvatarPath) == ["avatars/current.jpg", "avatars/current.jpg"])
        #expect(oldMessage.senderNickname == "변경 전")
        #expect(oldMessage.senderAvatarPath == "avatars/old.jpg")
    }

    @Test
    func missingProfileKeepsMessageSnapshotAsFallback() {
        let message = makeMessage(
            id: "message",
            nickname: "snapshot",
            avatarPath: "avatars/snapshot.jpg"
        )

        let resolved = RoomPreviewProfileOverlay.apply(
            to: [message],
            profileForUserID: { _ in nil }
        )

        #expect(resolved == [message])
    }

    private func makeMessage(
        id: String,
        nickname: String,
        avatarPath: String?
    ) -> ChatMessage {
        ChatMessage(
            ID: id,
            seq: 1,
            roomID: "room-1",
            senderUID: "user-1",
            senderEmail: nil,
            senderNickname: nickname,
            senderAvatarPath: avatarPath,
            messageType: .text,
            msg: "message",
            sentAt: Date(),
            attachments: [],
            sharedContent: nil,
            replyPreview: nil,
            isFailed: false,
            isDeleted: false
        )
    }
}
