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
    var imageStorageRepository: FirebaseImageStorageRepositoryProtocol { get }
    var videoStorageRepository: FirebaseVideoStorageRepositoryProtocol { get }
    var messageRepository: FirebaseMessageRepositoryProtocol { get }
    var mediaIndexRepository: FirebaseChatRoomMediaIndexRepositoryProtocol { get }
    var announcementRepository: FirebaseAnnouncementRepositoryProtocol { get }
}

struct FirebaseRepositoryProvider: FirebaseRepositoryProviding {
    let userProfileRepository: UserProfileRepositoryProtocol
    let chatRoomRepository: FirebaseChatRoomRepositoryProtocol
    let imageStorageRepository: FirebaseImageStorageRepositoryProtocol
    let videoStorageRepository: FirebaseVideoStorageRepositoryProtocol
    let messageRepository: FirebaseMessageRepositoryProtocol
    let mediaIndexRepository: FirebaseChatRoomMediaIndexRepositoryProtocol
    let announcementRepository: FirebaseAnnouncementRepositoryProtocol

    init(
        userProfileRepository: UserProfileRepositoryProtocol,
        chatRoomRepository: FirebaseChatRoomRepositoryProtocol,
        imageStorageRepository: FirebaseImageStorageRepositoryProtocol,
        videoStorageRepository: FirebaseVideoStorageRepositoryProtocol,
        messageRepository: FirebaseMessageRepositoryProtocol,
        mediaIndexRepository: FirebaseChatRoomMediaIndexRepositoryProtocol,
        announcementRepository: FirebaseAnnouncementRepositoryProtocol
    ) {
        self.userProfileRepository = userProfileRepository
        self.chatRoomRepository = chatRoomRepository
        self.imageStorageRepository = imageStorageRepository
        self.videoStorageRepository = videoStorageRepository
        self.messageRepository = messageRepository
        self.mediaIndexRepository = mediaIndexRepository
        self.announcementRepository = announcementRepository
    }

    static let shared: FirebaseRepositoryProviding = {
        let db = Firestore.firestore()
        let mediaIndexRepository = FirebaseChatRoomMediaIndexRepository(db: db)
        return FirebaseRepositoryProvider(
            userProfileRepository: UserProfileRepository(db: db),
            chatRoomRepository: FirebaseChatRoomRepository(db: db),
            imageStorageRepository: FirebaseImageStorageRepository.shared,
            videoStorageRepository: FirebaseVideoStorageRepository.shared,
            messageRepository: FirebaseMessageRepository(
                db: db,
                mediaIndexRepository: mediaIndexRepository
            ),
            mediaIndexRepository: mediaIndexRepository,
            announcementRepository: FirebaseAnnouncementRepository(db: db)
        )
    }()
}
