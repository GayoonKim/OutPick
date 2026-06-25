//
//  JoinedRoomsSessionStore.swift
//  OutPick
//
//  Created by Codex on 6/25/26.
//

import Foundation

@MainActor
protocol JoinedRoomsSessionStoring: AnyObject {
    var joined: Set<String> { get }

    func replace<S: Sequence>(with ids: S) where S.Element == String
    func add(_ roomID: String)
    func remove(_ roomID: String)
    func contains(_ id: String) -> Bool
    func clear()
}

@MainActor
final class JoinedRoomsSessionStore: JoinedRoomsSessionStoring {
    private(set) var joined: Set<String> = []

    func replace<S: Sequence>(with ids: S) where S.Element == String {
        let new = Set(ids)
        guard new != joined else { return }

        joined = new
    }

    func add(_ roomID: String) {
        guard !roomID.isEmpty else { return }
        guard !joined.contains(roomID) else { return }
        joined.insert(roomID)
    }

    func remove(_ roomID: String) {
        guard !roomID.isEmpty else { return }
        guard joined.remove(roomID) != nil else { return }
    }

    func contains(_ id: String) -> Bool { joined.contains(id) }

    func clear() {
        joined.removeAll()
    }
}
