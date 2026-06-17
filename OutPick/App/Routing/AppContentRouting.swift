//
//  AppContentRouting.swift
//  OutPick
//
//  Created by Codex on 6/17/26.
//

import Foundation

@MainActor
protocol AppContentRouting: AnyObject {
    func openJoinedChatRoom(roomID: String) async throws
    func openLookbookSharedContent(_ content: LookbookSharedContent) async throws
}
