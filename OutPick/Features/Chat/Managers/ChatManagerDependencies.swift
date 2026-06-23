//
//  ChatManagerProvider.swift
//  OutPick
//
//  Created by 김가윤 on 12/17/25.
//

import Foundation

protocol ChatManagerProviding {
    var messageManager: ChatMessageManaging { get }
    var roomImageManager: RoomImageManaging { get }
    var avatarImageManager: ChatAvatarImageManaging { get }
    var searchManager: ChatSearchManaging { get }
    var profileSyncManager: ChatProfileSyncManaging { get }
    var networkStatusProvider: NetworkStatusProviding { get }
}

struct ChatManagerProvider: ChatManagerProviding {
    let messageManager: ChatMessageManaging
    let roomImageManager: RoomImageManaging
    let avatarImageManager: ChatAvatarImageManaging
    let searchManager: ChatSearchManaging
    let profileSyncManager: ChatProfileSyncManaging
    let networkStatusProvider: NetworkStatusProviding

    init(
        repositories: FirebaseRepositoryProviding = FirebaseRepositoryProvider.shared,
        messageManager: ChatMessageManaging? = nil,
        roomImageManager: RoomImageManaging? = nil,
        avatarImageManager: ChatAvatarImageManaging? = nil,
        searchManager: ChatSearchManaging? = nil,
        profileSyncManager: ChatProfileSyncManaging = ChatProfileSyncManager(),
        networkStatusProvider: NetworkStatusProviding = NWPathNetworkStatusProvider()
    ) {
        let resolvedNetworkStatusProvider = networkStatusProvider
        let resolvedSearchManager = searchManager ?? ChatSearchManager(
            messageRepository: repositories.messageRepository,
            networkStatusProvider: resolvedNetworkStatusProvider
        )

        self.messageManager = messageManager ?? ChatMessageManager(
            messageRepository: repositories.messageRepository,
            imageStorageRepository: repositories.imageStorageRepository
        )
        self.roomImageManager = roomImageManager ?? RoomImageService(
            imageStorageRepository: repositories.imageStorageRepository
        )
        self.avatarImageManager = avatarImageManager ?? AvatarImageService(
            imageStorageRepository: repositories.imageStorageRepository
        )
        self.searchManager = resolvedSearchManager
        self.profileSyncManager = profileSyncManager
        self.networkStatusProvider = resolvedNetworkStatusProvider
        self.networkStatusProvider.startMonitoring()
    }
}
