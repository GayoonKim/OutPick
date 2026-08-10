//
//  ChatRoomVisibilityRuntimeManager.swift
//  OutPick
//
//  Created by Codex on 6/18/26.
//

import Foundation

@MainActor
protocol ChatRoomVisibilityRuntimeManaging {
    func enterVisibleRoom(roomID: String)
    func leaveVisibleRoom(roomID: String)
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

    func enterVisibleRoom(roomID: String) {
        bannerManager.setVisibleRoom(roomID)
        guard !roomID.isEmpty else { return }
        Task { @MainActor [presenceManager] in
            await presenceManager.enterRoom(roomID)
        }
    }

    func leaveVisibleRoom(roomID: String) {
        bannerManager.clearVisibleRoom(ifMatching: roomID)
        Task { @MainActor [presenceManager] in
            await presenceManager.leaveCurrentRoom()
        }
    }
}
