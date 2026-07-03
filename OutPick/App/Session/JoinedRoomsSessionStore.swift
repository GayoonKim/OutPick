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
    func changeStream() -> AsyncStream<Set<String>>
}

@MainActor
final class JoinedRoomsSessionStore: JoinedRoomsSessionStoring {
    private(set) var joined: Set<String> = []
    private var continuations: [UUID: AsyncStream<Set<String>>.Continuation] = [:]

    func replace<S: Sequence>(with ids: S) where S.Element == String {
        let new = Set(ids)
        guard new != joined else { return }

        joined = new
        emitSnapshot()
    }

    func add(_ roomID: String) {
        guard !roomID.isEmpty else { return }
        guard !joined.contains(roomID) else { return }
        joined.insert(roomID)
        emitSnapshot()
    }

    func remove(_ roomID: String) {
        guard !roomID.isEmpty else { return }
        guard joined.remove(roomID) != nil else { return }
        emitSnapshot()
    }

    func contains(_ id: String) -> Bool { joined.contains(id) }

    func clear() {
        guard !joined.isEmpty else { return }
        joined.removeAll()
        emitSnapshot()
    }

    func changeStream() -> AsyncStream<Set<String>> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.yield(joined)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.continuations.removeValue(forKey: id)
                }
            }
        }
    }

    private func emitSnapshot() {
        let snapshot = joined
        for continuation in continuations.values {
            continuation.yield(snapshot)
        }
    }
}
