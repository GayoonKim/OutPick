//
//  CommentAuthorProfileStore.swift
//  OutPick
//
//  Created by Codex on 5/5/26.
//

import Foundation

@MainActor
final class CommentAuthorProfileStore {
    private(set) var authorDisplays: [UserID: CommentAuthorDisplay] = [:]

    private let userProfileRepository: UserProfileRepositoryProtocol
    private let maxRetryCount: Int
    private let retryDelayNanoseconds: UInt64

    init(
        userProfileRepository: UserProfileRepositoryProtocol = FirebaseRepositoryProvider.shared.userProfileRepository,
        maxRetryCount: Int = 2,
        retryDelayNanoseconds: UInt64 = 300_000_000
    ) {
        self.userProfileRepository = userProfileRepository
        self.maxRetryCount = max(0, maxRetryCount)
        self.retryDelayNanoseconds = retryDelayNanoseconds
    }

    func displayItem(for comment: Comment) -> CommentDisplayItem {
        CommentDisplayItem(
            comment: comment,
            author: authorDisplays[comment.userID] ?? .unknown(userID: comment.userID)
        )
    }

    func loadMissingAuthors(for comments: [Comment]) async {
        let missingUserIDs = Array(
            Set(comments.map(\.userID))
                .filter { authorDisplays[$0] == nil }
        )
        guard missingUserIDs.isEmpty == false else { return }

        let profiles = await fetchProfilesWithRetry(userIDs: missingUserIDs)
        var nextAuthorDisplays = authorDisplays

        for userID in missingUserIDs {
            if let profile = profiles[userID] {
                nextAuthorDisplays[userID] = Self.makeAuthorDisplay(
                    userID: userID,
                    profile: profile
                )
            } else {
                nextAuthorDisplays[userID] = .unknown(userID: userID)
            }
        }

        authorDisplays = nextAuthorDisplays
    }

    func seedCurrentUserProfileIfPossible() {
        guard let userID = currentUserID else { return }
        guard let profile = LoginManager.shared.currentUserProfile else { return }

        authorDisplays[userID] = Self.makeAuthorDisplay(
            userID: userID,
            profile: profile
        )
    }

    func reset() {
        authorDisplays = [:]
    }

    private func fetchProfilesWithRetry(userIDs: [UserID]) async -> [UserID: UserProfile] {
        var remainingUserIDs = Set(userIDs)
        var profilesByUserID: [UserID: UserProfile] = [:]

        for attempt in 0...maxRetryCount {
            guard remainingUserIDs.isEmpty == false else { break }

            let rawUserIDs = remainingUserIDs.map(\.value)
            let fetchedProfiles = (try? await userProfileRepository.fetchUserProfiles(userIDs: rawUserIDs)) ?? [:]

            for userID in remainingUserIDs {
                if let profile = fetchedProfiles[userID.value] {
                    profilesByUserID[userID] = profile
                }
            }

            remainingUserIDs.subtract(profilesByUserID.keys)

            if remainingUserIDs.isEmpty || attempt == maxRetryCount {
                break
            }

            try? await Task.sleep(nanoseconds: retryDelayNanoseconds)
        }

        return profilesByUserID
    }

    private static func makeAuthorDisplay(
        userID: UserID,
        profile: UserProfile
    ) -> CommentAuthorDisplay {
        CommentAuthorDisplay(
            userID: userID,
            nickname: resolvedNickname(from: profile),
            avatarPath: profile.thumbPath ?? profile.originalPath
        )
    }

    private static func resolvedNickname(from profile: UserProfile) -> String {
        let nickname = profile.nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let nickname, nickname.isEmpty == false {
            return nickname
        }
        return "알 수 없는 사용자"
    }

    private var currentUserID: UserID? {
        let userID = LoginManager.shared.getAuthIdentityKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard userID.isEmpty == false else { return nil }
        return UserID(value: userID)
    }
}
