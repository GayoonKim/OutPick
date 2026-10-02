import Foundation

protocol UserBlockVisibilityChecking: AnyObject {
    func isBlocked(_ userID: String) -> Bool
    func blockedUserIDs() -> Set<String>
}

struct UserBlockVisibilitySnapshot: Equatable, Sendable {
    let accountID: String?
    let accountEpoch: UUID
    let revision: UInt64
    let isReady: Bool
    let blockedIDs: Set<String>
}

protocol UserBlockVisibilityObserving: UserBlockVisibilityChecking {
    func snapshot() -> UserBlockVisibilitySnapshot
    @MainActor func observe(_ callback: @escaping @MainActor (UserBlockVisibilitySnapshot) -> Void) -> UUID
    @MainActor func removeObserver(_ id: UUID)
}

final class UserBlockVisibilityStore: UserBlockVisibilityObserving, @unchecked Sendable {
    private let lock = NSLock()
    private var blockedIDs: Set<String>
    private var accountID: String?
    private var accountEpoch = UUID()
    private var revision: UInt64 = 0
    private var isReady = false
    @MainActor private var observers: [UUID: @MainActor (UserBlockVisibilitySnapshot) -> Void] = [:]

    init(blockedUserIDs: Set<String> = []) {
        self.blockedIDs = Self.normalized(blockedUserIDs)
    }

    func isBlocked(_ userID: String) -> Bool {
        let normalized = Self.normalized(userID)
        guard !normalized.isEmpty else { return false }
        lock.lock()
        defer { lock.unlock() }
        return blockedIDs.contains(normalized)
    }

    func blockedUserIDs() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return blockedIDs
    }

    func snapshot() -> UserBlockVisibilitySnapshot {
        lock.lock(); defer { lock.unlock() }
        return UserBlockVisibilitySnapshot(accountID: accountID, accountEpoch: accountEpoch,
            revision: revision, isReady: isReady, blockedIDs: blockedIDs)
    }

    @MainActor func observe(_ callback: @escaping @MainActor (UserBlockVisibilitySnapshot) -> Void) -> UUID {
        let id = UUID()
        observers[id] = callback
        callback(snapshot()) // 등록과 최초 전달 사이에는 다른 mutation이 끼어들지 않는다.
        return id
    }

    @MainActor func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }

    @MainActor @discardableResult
    func beginSession(accountID: String, cachedIDs: Set<String>?) -> UUID {
        mutate {
            self.accountID = accountID; accountEpoch = UUID(); isReady = cachedIDs != nil
            blockedIDs = Self.normalized(cachedIDs ?? [])
        }
        return snapshot().accountEpoch
    }

    @MainActor func activate(with userIDs: Set<String>) {
        mutate { blockedIDs = Self.normalized(userIDs); isReady = true }
    }

    @MainActor func replace(with userIDs: Set<String>) {
        mutate { blockedIDs = Self.normalized(userIDs) }
    }

    @MainActor func insert(_ userID: String) {
        let normalized = Self.normalized(userID)
        guard !normalized.isEmpty else { return }
        mutate { blockedIDs.insert(normalized) }
    }

    @MainActor func remove(_ userID: String) {
        let normalized = Self.normalized(userID)
        guard !normalized.isEmpty else { return }
        mutate { blockedIDs.remove(normalized) }
    }

    @MainActor func clear() {
        mutate { blockedIDs = []; accountID = nil; accountEpoch = UUID(); isReady = false }
    }

    @MainActor private func mutate(_ operation: () -> Void) {
        lock.lock()
        operation(); revision &+= 1
        lock.unlock()
        let value = snapshot()
        // 기존 차단 성공 호출 안에서 동기 전달한다. lock을 잡고 외부 callback을 호출하지 않는다.
        for callback in Array(observers.values) { callback(value) }
    }

    private static func normalized(_ userIDs: Set<String>) -> Set<String> {
        Set(userIDs.compactMap { userID in
            let normalized = normalized(userID)
            return normalized.isEmpty ? nil : normalized
        })
    }

    private static func normalized(_ userID: String) -> String {
        userID.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
