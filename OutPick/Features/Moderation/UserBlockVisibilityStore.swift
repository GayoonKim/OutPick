import Foundation

protocol UserBlockVisibilityChecking: AnyObject {
    func isBlocked(_ userID: String) -> Bool
    func blockedUserIDs() -> Set<String>
}

final class UserBlockVisibilityStore: UserBlockVisibilityChecking, @unchecked Sendable {
    private let lock = NSLock()
    private var blockedIDs: Set<String>

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

    func replace(with userIDs: Set<String>) {
        lock.lock()
        blockedIDs = Self.normalized(userIDs)
        lock.unlock()
    }

    func insert(_ userID: String) {
        let normalized = Self.normalized(userID)
        guard !normalized.isEmpty else { return }
        lock.lock()
        blockedIDs.insert(normalized)
        lock.unlock()
    }

    func remove(_ userID: String) {
        let normalized = Self.normalized(userID)
        guard !normalized.isEmpty else { return }
        lock.lock()
        blockedIDs.remove(normalized)
        lock.unlock()
    }

    func clear() {
        replace(with: [])
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
