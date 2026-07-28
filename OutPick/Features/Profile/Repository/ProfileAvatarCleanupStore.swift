import Foundation

protocol ProfileAvatarCleanupStoring {
    var pendingPaths: [String] { get }
    func enqueue(paths: [String])
    func remove(paths: [String])
}

final class UserDefaultsProfileAvatarCleanupStore: ProfileAvatarCleanupStoring {
    private let defaults: UserDefaults
    private let key = "profileAvatarCleanup.pendingPaths"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var pendingPaths: [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    func enqueue(paths: [String]) {
        let next = Array(Set(pendingPaths + paths.filter { !$0.isEmpty })).sorted()
        defaults.set(next, forKey: key)
    }

    func remove(paths: [String]) {
        let removed = Set(paths)
        let next = pendingPaths.filter { removed.contains($0) == false }
        defaults.set(next, forKey: key)
    }
}
