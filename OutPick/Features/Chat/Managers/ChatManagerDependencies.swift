//
//  ChatManagerProvider.swift
//  OutPick
//
//  Created by 김가윤 on 12/17/25.
//

import Foundation

struct ChatManagerProvider {
    let messageManager: ChatMessageManaging
    let roomImageManager: RoomImageManaging
    let searchManager: ChatSearchManaging
    let profileSyncManager: ChatProfileSyncManaging
    let networkStatusProvider: NetworkStatusProviding

    init(
        repositories: FirebaseRepositoryProviding = FirebaseRepositoryProvider.shared,
        persistence: ChatPersistenceProvider,
        messageManager: ChatMessageManaging? = nil,
        roomImageManager: RoomImageManaging? = nil,
        searchManager: ChatSearchManaging? = nil,
        profileSyncManager: ChatProfileSyncManaging? = nil,
        networkStatusProvider: NetworkStatusProviding = NWPathNetworkStatusProvider()
    ) {
        let resolvedNetworkStatusProvider = networkStatusProvider
        let resolvedSearchManager = searchManager ?? ChatSearchManager(
            messageSearch: persistence.messageStore,
            messageRepository: repositories.messageRepository,
            networkStatusProvider: resolvedNetworkStatusProvider
        )

        self.messageManager = messageManager ?? ChatMessageManager(
            messageRepository: repositories.messageRepository,
            imageStorageRepository: repositories.imageStorageRepository,
            messagePersistence: persistence.messageStore,
            profileCache: persistence.profileStore
        )
        self.roomImageManager = roomImageManager ?? RoomImageService(
            imageStorageRepository: repositories.imageStorageRepository
        )
        self.searchManager = resolvedSearchManager
        self.profileSyncManager = profileSyncManager ?? ChatProfileSyncManager(
            userProfileRepository: repositories.userProfileRepository,
            profileCache: persistence.profileStore
        )
        self.networkStatusProvider = resolvedNetworkStatusProvider
        self.networkStatusProvider.startMonitoring()
    }
}
