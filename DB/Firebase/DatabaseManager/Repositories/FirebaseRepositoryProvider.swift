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
    var chatRoomRepository: FirebaseChatRoomRepositoryProtocol { get }
    var messageRepository: FirebaseMessageRepositoryProtocol { get }
    var announcementRepository: FirebaseAnnouncementRepositoryProtocol { get }
}

struct FirebaseRepositoryProvider: FirebaseRepositoryProviding {
    let userProfileRepository: UserProfileRepositoryProtocol
    let chatRoomRepository: FirebaseChatRoomRepositoryProtocol
    let messageRepository: FirebaseMessageRepositoryProtocol
    let announcementRepository: FirebaseAnnouncementRepositoryProtocol

    init(
        userProfileRepository: UserProfileRepositoryProtocol,
        chatRoomRepository: FirebaseChatRoomRepositoryProtocol,
        messageRepository: FirebaseMessageRepositoryProtocol,
        announcementRepository: FirebaseAnnouncementRepositoryProtocol
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
            chatRoomRepository: FirebaseChatRoomRepository(db: db),
            messageRepository: FirebaseMessageRepository(db: db),
            announcementRepository: FirebaseAnnouncementRepository(db: db)
        )
    }()
}
