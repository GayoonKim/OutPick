//
//  ChatRoomVisibilityRuntimeManager.swift
//  OutPick
//
//  Created by Codex on 6/18/26.
//

import Foundation

@MainActor
protocol ChatRoomVisibilityRuntimeManaging {
    func enterVisibleRoom(roomID: String) async
    func leaveVisibleRoom() async
}

@MainActor
final class DefaultChatRoomVisibilityRuntimeManager: ChatRoomVisibilityRuntimeManaging {
    private let bannerManager: BannerManager
    private let presenceManager: PresenceManager

    init() {
        self.bannerManager = .shared
        self.presenceManager = .shared
    }

    init(
        bannerManager: BannerManager,
        presenceManager: PresenceManager
    ) {
        self.bannerManager = bannerManager
        self.presenceManager = presenceManager
    }

    func enterVisibleRoom(roomID: String) async {
        bannerManager.setVisibleRoom(roomID)
        guard !roomID.isEmpty else { return }
        await presenceManager.enterRoom(roomID)
    }

    func leaveVisibleRoom() async {
        bannerManager.setVisibleRoom(nil)
        await presenceManager.leaveCurrentRoom()
    }
}
