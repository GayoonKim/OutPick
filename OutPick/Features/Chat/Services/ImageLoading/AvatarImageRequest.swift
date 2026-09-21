import Foundation

enum AvatarImageLoadingError: Error {
    case unavailable
}

enum AvatarImageCachePolicy: Sendable {
    case memoryOnly
    case memoryAndDisk

    var storePolicy: ImageCacheStorePolicy {
        self == .memoryOnly ? .memoryOnly : .memoryAndDisk
    }
}

struct AvatarImageRequest: Sendable {
    static let thumbnailMaximumBytes = 3 * 1024 * 1024
    static let originalMaximumBytes = 20 * 1024 * 1024

    enum Representation: Sendable { case thumbnail, original }
    let path: String
    let representation: Representation
    let cachePolicy: AvatarImageCachePolicy

    var maximumBytes: Int {
        representation == .thumbnail ? Self.thumbnailMaximumBytes : Self.originalMaximumBytes
    }
    var storePolicy: ImageCacheStorePolicy {
        representation == .original ? .transient : cachePolicy.storePolicy
    }
}
