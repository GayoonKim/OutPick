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

/// 전역 DI 컨테이너 (앱 시작 시점/테스트에서 교체 가능)
enum ChatDependencyContainer {
    static var provider: ChatManagerProviding = ChatManagerProvider()
    static var firebaseRepositories: FirebaseRepositoryProviding?
    static var joinedRoomsStore: JoinedRoomsStore?

    static func requireFirebaseRepositories() -> FirebaseRepositoryProviding {
        guard let firebaseRepositories else {
            preconditionFailure("ChatDependencyContainer.firebaseRepositories is not configured")
        }
        return firebaseRepositories
    }

    static func requireJoinedRoomsStore() -> JoinedRoomsStore {
        guard let joinedRoomsStore else {
            preconditionFailure("ChatDependencyContainer.joinedRoomsStore is not configured")
        }
        return joinedRoomsStore
    }
}
