enum ChatProfileRecordMapper {
    static func record(from user: LocalChatUser) -> LocalChatUserRecord {
        LocalChatUserRecord(userID: user.userID, nickname: user.nickname, profileImagePath: user.profileImagePath)
    }

    static func model(from record: LocalChatUserRecord) -> LocalChatUser {
        LocalChatUser(userID: record.userID, nickname: record.nickname, profileImagePath: record.profileImagePath)
    }
}
