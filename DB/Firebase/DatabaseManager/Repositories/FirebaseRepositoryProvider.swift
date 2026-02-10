//
//  FirebaseRepositoryProvider.swift
//  OutPick
//
//  Created by Codex on 2/11/26.
//

import Foundation
import FirebaseFirestore

protocol FirebaseRepositoryProviding {
    var userProfileRepository: UserProfileRepositoryProtocol { get }
    var chatRoomRepository: ChatRoomRepositoryProtocol { get }
    var messageRepository: MessageRepositoryProtocol { get }
    var announcementRepository: AnnouncementRepositoryProtocol { get }
}

struct FirebaseRepositoryProvider: FirebaseRepositoryProviding {
    let userProfileRepository: UserProfileRepositoryProtocol
    let chatRoomRepository: ChatRoomRepositoryProtocol
    let messageRepository: MessageRepositoryProtocol
    let announcementRepository: AnnouncementRepositoryProtocol

    init(
        userProfileRepository: UserProfileRepositoryProtocol,
        chatRoomRepository: ChatRoomRepositoryProtocol,
        messageRepository: MessageRepositoryProtocol,
        announcementRepository: AnnouncementRepositoryProtocol
    ) {
        self.userProfileRepository = userProfileRepository
        self.chatRoomRepository = chatRoomRepository
        self.messageRepository = messageRepository
        self.announcementRepository = announcementRepository
    }

    static let shared: FirebaseRepositoryProviding = {
        let db = Firestore.firestore()
        return FirebaseRepositoryProvider(
            userProfileRepository: UserProfileRepository(db: db),
            chatRoomRepository: ChatRoomRepository(db: db),
            messageRepository: MessageRepository(db: db),
            announcementRepository: AnnouncementRepository(db: db)
        )
    }()
}
