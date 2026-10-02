//
//  ChatManagerProvider.swift
//  OutPick
//
//  Created by 김가윤 on 12/17/25.
//

import Foundation

@MainActor struct ChatManagerProvider {
    let messageManager: ChatMessageManaging
    let roomImageManager: RoomImageManaging
    let searchSessionManager: ChatSearchSessionManaging
    let profileSyncManager: ChatProfileSyncManaging
    let networkStatusProvider: NetworkStatusProviding

    init(
        repositories: FirebaseRepositoryProviding = FirebaseRepositoryProvider.shared,
        publicProfileRepository: UserPublicProfileRepositoryProtocol,
        persistence: ChatPersistenceProvider,
        messageManager: ChatMessageManaging? = nil,
        roomImageManager: RoomImageManaging? = nil,
        profileSyncManager: ChatProfileSyncManaging? = nil,
        moderationLifecycleRepository: ChatModerationLifecycleRepositoryProtocol =
            CloudFunctionsChatModerationLifecycleRepository(),
        deletionSanitizer: ChatDeletionSyncUseCaseProtocol? = nil,
        searchVisibility: (any UserBlockVisibilityObserving)? = nil,
        searchDeletionFence: ChatSearchDeletionFence,
        cacheSession: ChatMessageCacheSession = ChatMessageCacheSession(),
        currentAccountID: @escaping @Sendable () -> String = { LoginManager.shared.canonicalUserID },
        networkStatusProvider: NetworkStatusProviding = NWPathNetworkStatusProvider()
    ) {
        let resolvedNetworkStatusProvider = networkStatusProvider
        self.messageManager = messageManager ?? ChatMessageManager(
            messageRepository: repositories.messageRepository,
            moderationLifecycleRepository: moderationLifecycleRepository,
            messagePersistence: persistence.messageStore,
            profileCache: persistence.profileStore,
            deletionSanitizer: deletionSanitizer,
            cacheSession: cacheSession,
            currentAccountID: currentAccountID,
            networkStatusProvider: resolvedNetworkStatusProvider
        )
        self.roomImageManager = roomImageManager ?? RoomImageService(
            imageStorageRepository: repositories.imageStorageRepository
        )
        self.searchSessionManager = ChatSearchSessionController(remote: repositories.messageRepository,
            local: persistence.searchLocalReader, store: persistence.searchStore, visibility: searchVisibility,
            validation: ChatSearchValidationRepository(access: moderationLifecycleRepository, deletion: deletionSanitizer,
                currentAccountID: currentAccountID), network: resolvedNetworkStatusProvider, deletionFence: searchDeletionFence)
        self.profileSyncManager = profileSyncManager ?? ChatProfileSyncManager(
            publicProfileRepository: publicProfileRepository,
            profileCache: persistence.profileStore
        )
        self.networkStatusProvider = resolvedNetworkStatusProvider
        self.networkStatusProvider.startMonitoring()
    }
}
