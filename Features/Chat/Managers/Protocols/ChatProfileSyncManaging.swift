//
//  ChatProfileSyncManaging.swift
//  OutPick
//
//  Created by Codex on 3/17/26.
//

import Foundation
import Combine

protocol ChatProfileSyncManaging {
    func activateScope(_ scopeID: UUID, roomID: String, initialMessages: [ChatMessage])
    func ingestMessages(_ messages: [ChatMessage], into scopeID: UUID)
    func changedSenderIDsPublisher(scopeID: UUID) -> AnyPublisher<Set<String>, Never>
    func profile(for email: String) -> LocalUser?
    func deactivateScope(_ scopeID: UUID)
}
