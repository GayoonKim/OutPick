//
//  ChatManagerProvider.swift
//  OutPick
//
//  Created by 김가윤 on 12/17/25.
//

import Foundation

protocol ChatManagerProviding {
    var messageManager: ChatMessageManaging { get }
    var mediaManager: ChatMediaManaging { get }
    var roomImageManager: RoomImageManaging { get }
    var avatarImageManager: ChatAvatarImageManaging { get }
    var searchManager: ChatSearchManaging { get }
    var profileSyncManager: ChatProfileSyncManaging { get }
    var networkStatusProvider: NetworkStatusProviding { get }
}

struct ChatManagerProvider: ChatManagerProviding {
    let messageManager: ChatMessageManaging
    let mediaManager: ChatMediaManaging
    let roomImageManager: RoomImageManaging
    let avatarImageManager: ChatAvatarImageManaging
    let searchManager: ChatSearchManaging
    let profileSyncManager: ChatProfileSyncManaging
    let networkStatusProvider: NetworkStatusProviding

    init(
        messageManager: ChatMessageManaging = ChatMessageManager(),
        mediaManager: ChatMediaManaging = ChatMediaManager.shared,
        roomImageManager: RoomImageManaging = RoomImageService.shared,
        avatarImageManager: ChatAvatarImageManaging = AvatarImageService.shared,
        searchManager: ChatSearchManaging? = nil,
        profileSyncManager: ChatProfileSyncManaging = ChatProfileSyncManager(),
        networkStatusProvider: NetworkStatusProviding = NWPathNetworkStatusProvider()
    ) {
        let resolvedNetworkStatusProvider = networkStatusProvider
        let resolvedSearchManager = searchManager ?? ChatSearchManager(
            messageRepository: FirebaseRepositoryProvider.shared.messageRepository,
            networkStatusProvider: resolvedNetworkStatusProvider
        )

        self.messageManager = messageManager
        self.mediaManager = mediaManager
        self.roomImageManager = roomImageManager
        self.avatarImageManager = avatarImageManager
        self.searchManager = resolvedSearchManager
        self.profileSyncManager = profileSyncManager
        self.networkStatusProvider = resolvedNetworkStatusProvider
        self.networkStatusProvider.startMonitoring()
    }
}
