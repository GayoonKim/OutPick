import Foundation
import Kingfisher

@MainActor
protocol AccountDeletionLocalDataScrubbing {
    var requiresRetry: Bool { get }
    func scrub() async throws
}

enum AccountDeletionLocalDataScrubError: Error {
    case database(Error)
}

@MainActor
final class AccountDeletionLocalDataScrubber: AccountDeletionLocalDataScrubbing {
    private let database: AppDatabase
    private let loginManager: LoginManager
    private let defaults: UserDefaults
    private let markerKey: String

    init(
        database: AppDatabase,
        loginManager: LoginManager = .shared,
        defaults: UserDefaults = .standard,
        markerKey: String = "AccountDeletionLocalCleanupPending"
    ) {
        self.database = database
        self.loginManager = loginManager
        self.defaults = defaults
        self.markerKey = markerKey
    }

    var requiresRetry: Bool {
        defaults.bool(forKey: markerKey)
    }

    func scrub() async throws {
        defaults.set(true, forKey: markerKey)
        var databaseError: Error?
        do {
            try await database.deleteAllUserSessionData()
        } catch {
            databaseError = error
        }

        [
            "recentSearches",
            "isRecentSearchEnabled",
            "profileAvatarCleanup.pendingPaths"
        ].forEach(defaults.removeObject(forKey:))

        await ImageCachePipeline.removeAllRegisteredCaches()
        for folderName in [
            "ImageCache",
            "LookbookRemotePreviewImageCache",
            "AvatarImageCache",
            "RoomCoverImageCache",
            "ChatImageCache",
            "ThumbCache"
        ] {
            await ImageCacheDiskStore(folderName: folderName).removeAll()
        }
        KingfisherManager.shared.cache.clearMemoryCache()
        await withCheckedContinuation { continuation in
            KingfisherManager.shared.cache.clearDiskCache {
                continuation.resume()
            }
        }
        await loginManager.clearSessionForAccountDeletion()

        if let databaseError {
            throw AccountDeletionLocalDataScrubError.database(databaseError)
        }
        defaults.removeObject(forKey: markerKey)
    }
}
