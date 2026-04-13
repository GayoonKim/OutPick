//
//  AvatarImageSource.swift
//  OutPick
//

import Foundation

struct AvatarImageSource: Equatable, Hashable {
    var thumbnailPath: String?
    var originalPath: String?

    init(
        thumbnailPath: String? = nil,
        originalPath: String? = nil
    ) {
        self.thumbnailPath = Self.normalize(thumbnailPath)
        self.originalPath = Self.normalize(originalPath)
    }

    init(seedPath: String?) {
        let normalized = Self.normalize(seedPath)
        self.init(thumbnailPath: normalized, originalPath: nil)
    }

    var hasImagePath: Bool {
        immediateDisplayPath != nil || viewerOriginalPath != nil
    }

    var immediateDisplayPath: String? {
        thumbnailPath ?? originalPath
    }

    var viewerThumbnailPath: String? {
        thumbnailPath ?? originalPath
    }

    var viewerOriginalPath: String? {
        originalPath ?? thumbnailPath
    }

    var upgradeOriginalPath: String? {
        guard let originalPath else { return nil }
        guard originalPath != immediateDisplayPath else { return nil }
        return originalPath
    }

    func merged(with profile: UserProfile) -> AvatarImageSource {
        var merged = self

        if let thumbPath = Self.normalize(profile.thumbPath) {
            merged.thumbnailPath = thumbPath
        }

        if let originalPath = Self.normalize(profile.originalPath) {
            merged.originalPath = originalPath
        }

        return merged
    }

    private static func normalize(_ path: String?) -> String? {
        guard let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
