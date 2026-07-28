//
//  CommentAuthorProfileStore.swift
//  OutPick
//
//  Created by Codex on 5/5/26.
//

import Foundation
import FirebaseFirestore

@MainActor
final class CommentAuthorProfileStore {
    private(set) var authorDisplays: [UserID: CommentAuthorDisplay] = [:]

    private let publicProfileRepository: UserPublicProfileRepositoryProtocol
    private let currentUserIDProvider: any CurrentUserIDProviding
    private let currentUserProvider: any CurrentUserProviding
    private let maxRetryCount: Int
    private let retryDelayNanoseconds: UInt64

    init(
        publicProfileRepository: UserPublicProfileRepositoryProtocol =
            FirestoreUserPublicProfileRepository(db: .firestore()),
        currentUserIDProvider: any CurrentUserIDProviding = LoginManagerCurrentUserIDProvider(),
        currentUserProvider: any CurrentUserProviding = LoginManagerCurrentUserProvider(),
        maxRetryCount: Int = 2,
        retryDelayNanoseconds: UInt64 = 300_000_000
    ) {
        self.publicProfileRepository = publicProfileRepository
        self.currentUserIDProvider = currentUserIDProvider
        self.currentUserProvider = currentUserProvider
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
        apply(profiles: profiles)
    }

    func refreshAuthors(for comments: [Comment]) async {
        let userIDs = Array(Set(comments.map(\.userID)))
        guard userIDs.isEmpty == false else { return }

        let profiles = await fetchProfilesWithRetry(userIDs: userIDs)
        apply(profiles: profiles)
    }

    private func apply(profiles: [UserID: UserPublicProfile]) {
        guard profiles.isEmpty == false else { return }
        var nextAuthorDisplays = authorDisplays

        for (userID, profile) in profiles {
            nextAuthorDisplays[userID] = Self.makeAuthorDisplay(
                userID: userID,
                profile: profile
            )
        }

        authorDisplays = nextAuthorDisplays
    }

    func seedCurrentUserProfileIfPossible() {
        guard let userID = currentUserID else { return }
        guard let profile = currentUserProvider.profile else { return }

        authorDisplays[userID] = Self.makeAuthorDisplay(
            userID: userID,
            profile: profile
        )
    }

    func reset() {
        authorDisplays = [:]
    }

    private func fetchProfilesWithRetry(userIDs: [UserID]) async -> [UserID: UserPublicProfile] {
        var remainingUserIDs = Set(userIDs)
        var profilesByUserID: [UserID: UserPublicProfile] = [:]

        for attempt in 0...maxRetryCount {
            guard remainingUserIDs.isEmpty == false else { break }

            let rawUserIDs = remainingUserIDs.map(\.value)
            let fetchedProfiles = (try? await publicProfileRepository.fetchProfiles(userIDs: rawUserIDs)) ?? [:]

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
        profile: UserPublicProfile
    ) -> CommentAuthorDisplay {
        CommentAuthorDisplay(
            userID: userID,
            nickname: resolvedNickname(from: profile),
            avatarPath: profile.avatarThumbPath ?? profile.avatarOriginalPath
        )
    }

    private static func resolvedNickname(from profile: UserPublicProfile) -> String {
        let nickname = profile.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if nickname.isEmpty == false {
            return nickname
        }
        return "알 수 없는 사용자"
    }

    private var currentUserID: UserID? {
        currentUserIDProvider.currentUserID
    }
}
