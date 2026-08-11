import Foundation

protocol UserBlockSnapshotPersisting {
    func load(userID: String) -> Set<String>?
    func save(_ blockedUserIDs: Set<String>, userID: String)
    func removeAllSnapshots()
}

final class UserDefaultsUserBlockSnapshotStore: UserBlockSnapshotPersisting {
    static let keyPrefix = "moderation.blockedUserIDs."

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(userID: String) -> Set<String>? {
        let key = snapshotKey(userID: userID)
        guard defaults.object(forKey: key) != nil else { return nil }
        let values = defaults.stringArray(forKey: key) ?? []
        return Set(values.compactMap(Self.normalized))
    }

    func save(_ blockedUserIDs: Set<String>, userID: String) {
        let normalized = blockedUserIDs.compactMap(Self.normalized).sorted()
        defaults.set(normalized, forKey: snapshotKey(userID: userID))
    }

    func removeAllSnapshots() {
        defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(Self.keyPrefix) }
            .forEach(defaults.removeObject(forKey:))
    }

    private func snapshotKey(userID: String) -> String {
        Self.keyPrefix + Data(userID.utf8).base64EncodedString()
    }

    private static func normalized(_ rawValue: String) -> String? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("/") else { return nil }
        return value
    }
}
