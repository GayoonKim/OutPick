import Foundation
import GRDB
@testable import OutPick

enum TemporaryAppDatabase {
    static func make() throws -> AppDatabase {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OutPick-GRDB-Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pool = try DatabasePool(path: directory.appendingPathComponent("OutPick.sqlite").path)
        return try AppDatabase(dbPool: pool)
    }
}

enum GRDBTestFixtures {
    static func message(
        id: String = UUID().uuidString,
        roomID: String = "room-1",
        seq: Int64 = 1,
        senderUID: String = "user-1",
        text: String = "hello",
        attachments: [Attachment] = [],
        isFailed: Bool = false
    ) -> ChatMessage {
        ChatMessage(
            ID: id,
            seq: seq,
            roomID: roomID,
            senderUID: senderUID,
            senderEmail: nil,
            senderNickname: "User",
            senderAvatarPath: nil,
            messageType: .text,
            msg: text,
            sentAt: Date(timeIntervalSince1970: TimeInterval(seq)),
            attachments: attachments,
            sharedContent: nil,
            replyPreview: nil,
            isFailed: isFailed,
            isDeleted: false
        )
    }
}
