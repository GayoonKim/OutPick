import Foundation

/// 알려진 삭제의 DB 반영 전에 검색 발행과 이동을 동기 무효화한다.
@MainActor final class ChatSearchDeletionFence {
    private var observers: [UUID: (String) -> Void] = [:]
    private var pending: [UUID: String] = [:]
    private var revisions: [String: UInt64] = [:]
    private var failed: [String: UInt64] = [:]
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    func observe(_ callback: @escaping (String) -> Void) -> UUID {
        let id = UUID(); observers[id] = callback; return id
    }
    func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }
    func begin(roomID: String) -> UUID {
        let id = UUID()
        pending[id] = roomID
        revisions[roomID, default: 0] &+= 1
        for callback in Array(observers.values) { callback(roomID) }
        return id
    }
    func finish(_ id: UUID, succeeded: Bool) {
        guard let room = pending.removeValue(forKey: id) else { return }
        if !succeeded { failed[room] = revisions[room, default: 0] }
        if !pending.values.contains(room) {
            let callbacks = waiters.removeValue(forKey: room) ?? []
            callbacks.forEach { $0.resume() }
        }
    }
    func waitForWrites(roomID: String) async {
        while pending.values.contains(roomID) {
            await withCheckedContinuation { waiters[roomID, default: []].append($0) }
        }
    }
    func revision(roomID: String) -> UInt64 { revisions[roomID, default: 0] }
    func reconciled(roomID: String, through revision: UInt64) {
        if let value = failed[roomID], value <= revision { failed.removeValue(forKey: roomID) }
    }
    func requireHealthy(roomID: String) throws {
        if failed[roomID] != nil { throw ChatSearchFailure.localStorage }
    }
}

protocol ChatSearchValidating {
    func validateAccess(accountID: String, roomID: String) async throws
    func reconcileDeletion(accountID: String, roomID: String) async throws
}
