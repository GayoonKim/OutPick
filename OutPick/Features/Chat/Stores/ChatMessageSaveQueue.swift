import Foundation

/// 화면 수명과 독립된 계정 세션 fence다. DB transaction 안에서도 확인한다.
final class ChatMessageCacheSession: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    private var invalidRooms: Set<String> = []
    private var roomGenerations: [String: UInt64] = [:]
    private let parentValidation: @Sendable () -> Bool

    init(validation: @escaping @Sendable () -> Bool = { true }) { parentValidation = validation }

    func isValid(roomID: String) -> Bool {
        guard parentValidation() else { return false }
        lock.lock(); defer { lock.unlock() }
        return active && !invalidRooms.contains(roomID)
    }

    func invalidate(roomID: String? = nil) {
        lock.lock(); defer { lock.unlock() }
        if let roomID {
            invalidRooms.insert(roomID)
            roomGenerations[roomID, default: 0] &+= 1
        } else { active = false }
    }

    func activate(roomID: String) {
        lock.lock(); defer { lock.unlock() }
        invalidRooms.remove(roomID)
    }

    func snapshot(roomID: String) -> ChatMessageCacheSession {
        lock.lock()
        let generation = roomGenerations[roomID, default: 0]
        lock.unlock()
        return ChatMessageCacheSession { [self] in
            guard self.isValid(roomID: roomID) else { return false }
            self.lock.lock(); defer { self.lock.unlock() }
            return self.active && !self.invalidRooms.contains(roomID) && self.roomGenerations[roomID, default: 0] == generation
        }
    }
}

actor ChatMessageSaveQueue {
    typealias Save = @Sendable (ChatMessage) async throws -> Void
    private struct Key: Hashable { let roomID: String; let messageID: String }
    private struct Item { let message: ChatMessage; let save: Save; let confirm: Save; let session: ChatMessageCacheSession }
    private var pending: [Key: Item] = [:]
    private var order: [Key] = []
    private var draining = false
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    private let session: ChatMessageCacheSession

    init(session: ChatMessageCacheSession) { self.session = session }

    func waitUntilIdle() async {
        guard draining else { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    func enqueue(_ message: ChatMessage, save: @escaping Save, confirm: @escaping Save) {
        guard session.isValid(roomID: message.roomID) else { return }
        let key = Key(roomID: message.roomID, messageID: message.ID)
        if let current = pending[key], current.session.isValid(roomID: message.roomID) {
            guard let merged = try? ChatMessageMergePolicy.preferred(current.message, message) else { return }
            pending[key] = Item(message: merged, save: save, confirm: confirm, session: current.session)
        } else {
            pending[key] = Item(message: message, save: save, confirm: confirm, session: session.snapshot(roomID: message.roomID))
            order.append(key)
        }
        guard !draining else { return }
        draining = true
        Task { await self.drain() }
    }

    private func drain() async {
        defer {
            draining = false
            let waiters = idleWaiters
            idleWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }
        while !order.isEmpty {
            let key = order.removeFirst()
            guard let first = pending[key] else { continue }
            var saved: ChatMessage?
            for _ in 0..<5 {
                guard first.session.isValid(roomID: key.roomID), let item = pending[key] else { break }
                do {
                    try await item.save(item.message)
                    saved = item.message
                    break
                } catch {
                    if error is CancellationError { break }
                }
            }
            if let saved, first.session.isValid(roomID: key.roomID) {
                // 메시지 write 성공 이후에만 outbox를 정리한다.
                try? await first.confirm(saved)
            }
            // 재참여로 같은 키의 새 작업이 들어온 경우 이전 작업이 제거하지 않는다.
            if let latest = pending[key], latest.session !== first.session { continue }
            if let saved, let latest = pending[key], !ChatMessageMergePolicy.samePayload(saved, latest.message),
               session.isValid(roomID: key.roomID) {
                order.append(key)
            } else {
                pending.removeValue(forKey: key)
            }
        }
    }
}
