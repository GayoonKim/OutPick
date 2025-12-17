//
//  ChatRepositoryProvider.swift
//  OutPick
//
//  Created by 김가윤 on 12/17/25.
//

import Foundation

import Foundation

protocol ChatRepositoryProviding {
    var messageManager: ChatMessageManagerProtocol { get }
    var mediaManager: ChatMediaManagerProtocol { get }
    var searchManager: ChatSearchManagerProtocol { get }
    var hotUserManager: HotUserManagerProtocol { get }
}

struct ChatRepositoryProvider: ChatRepositoryProviding {
    let messageManager: ChatMessageManagerProtocol
    let mediaManager: ChatMediaManagerProtocol
    let searchManager: ChatSearchManagerProtocol
    let hotUserManager: HotUserManagerProtocol

    init(
        messageManager: ChatMessageManagerProtocol = ChatMessageManager(),
        mediaManager: ChatMediaManagerProtocol = ChatMediaManager(),
        searchManager: ChatSearchManagerProtocol = ChatSearchManager(),
        hotUserManager: HotUserManagerProtocol = HotUserManager()
    ) {
        self.messageManager = messageManager
        self.mediaManager = mediaManager
        self.searchManager = searchManager
        self.hotUserManager = hotUserManager
    }
}

/// 전역 DI 컨테이너 (앱 시작 시점/테스트에서 교체 가능)
enum ChatDependencyContainer {
    static var provider: ChatRepositoryProviding = ChatRepositoryProvider()
}
