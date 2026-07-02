//
//  ChatProfileSyncManaging.swift
//  OutPick
//
//  Created by Codex on 3/17/26.
//

import Foundation

protocol ChatProfileSyncManaging {
    @discardableResult
    func refreshProfiles(from messages: [ChatMessage]) async -> Set<String>
    func profile(for senderUID: String) -> LocalUser?
    func reset()
}
