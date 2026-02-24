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
    var searchManager: ChatSearchManaging { get }
    var hotUserManager: HotUserManaging { get }
}

struct ChatManagerProvider: ChatManagerProviding {
    let messageManager: ChatMessageManaging
    let mediaManager: ChatMediaManaging
    let searchManager: ChatSearchManaging
    let hotUserManager: HotUserManaging

    init(
        messageManager: ChatMessageManaging = ChatMessageManager(),
        mediaManager: ChatMediaManaging = ChatMediaManager(),
        searchManager: ChatSearchManaging = ChatSearchManager(),
        hotUserManager: HotUserManaging = HotUserManager()
    ) {
        self.messageManager = messageManager
        self.mediaManager = mediaManager
        self.searchManager = searchManager
        self.hotUserManager = hotUserManager
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
