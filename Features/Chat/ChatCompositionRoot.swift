//
//  ChatCompositionRoot.swift
//  OutPick
//
//  Created by Codex on 2/10/26.
//

import UIKit

/// Chat 탭 조립 전담 CompositionRoot
@MainActor
enum ChatCompositionRoot {
    static func makeRoomListRoot(coordinator: ChatCoordinator) -> UIViewController {
        coordinator.makeRoomListRoot()
    }

    static func makeJoinedRoomsRoot(coordinator: ChatCoordinator) -> UIViewController {
        coordinator.makeJoinedRoomsRoot()
    }
}
