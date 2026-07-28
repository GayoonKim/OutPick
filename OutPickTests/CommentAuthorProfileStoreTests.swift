import Foundation
import Testing
@testable import OutPick

struct CommentAuthorProfileStoreTests {
    @Test
    @MainActor
    func explicitRefreshRefetchesAnAlreadyCachedAuthor() async {
        let repository = CommentAuthorProfileRepositoryFake(responses: [
            .success(["author-1": makeProfile(nickname: "이전 닉네임", avatar: "old.jpg")]),
            .success(["author-1": makeProfile(nickname: "현재 닉네임", avatar: "current.jpg")])
        ])
        let store = makeStore(repository: repository)
        let comment = makeComment()

        await store.loadMissingAuthors(for: [comment])
        #expect(store.displayItem(for: comment).author.nickname == "이전 닉네임")

        await store.refreshAuthors(for: [comment])

        #expect(repository.fetchCallCount == 2)
        #expect(store.displayItem(for: comment).author.nickname == "현재 닉네임")
        #expect(store.displayItem(for: comment).author.avatarPath == "current.jpg")
    }

    @Test
    @MainActor
    func failedRefreshPreservesThePreviousDisplayProfile() async {
        let repository = CommentAuthorProfileRepositoryFake(responses: [
            .success(["author-1": makeProfile(nickname: "유지할 닉네임", avatar: "old.jpg")]),
            .failure(TestError.failed)
        ])
        let store = makeStore(repository: repository)
        let comment = makeComment()

        await store.loadMissingAuthors(for: [comment])
        await store.refreshAuthors(for: [comment])

        #expect(store.displayItem(for: comment).author.nickname == "유지할 닉네임")
        #expect(store.displayItem(for: comment).author.avatarPath == "old.jpg")
    }

    @Test
    @MainActor
    func aFailedMissingAuthorLoadCanBeRetried() async {
        let repository = CommentAuthorProfileRepositoryFake(responses: [
            .failure(TestError.failed),
            .success(["author-1": makeProfile(nickname: "재시도 성공", avatar: nil)])
        ])
        let store = makeStore(repository: repository)
        let comment = makeComment()

        await store.loadMissingAuthors(for: [comment])
        #expect(store.displayItem(for: comment).author.nickname == "알 수 없는 사용자")

        await store.loadMissingAuthors(for: [comment])

        #expect(repository.fetchCallCount == 2)
        #expect(store.displayItem(for: comment).author.nickname == "재시도 성공")
    }

    @MainActor
    private func makeStore(
        repository: CommentAuthorProfileRepositoryFake
    ) -> CommentAuthorProfileStore {
        CommentAuthorProfileStore(
            publicProfileRepository: repository,
            currentUserIDProvider: CommentAuthorCurrentUserIDFake(),
            currentUserProvider: CommentAuthorCurrentUserFake(),
            maxRetryCount: 0,
            retryDelayNanoseconds: 0
        )
    }

    private func makeComment() -> OutPick.Comment {
        OutPick.Comment(
            id: CommentID(value: "comment-1"),
            postID: PostID(value: "post-1"),
            userID: UserID(value: "author-1"),
            message: "댓글",
            createdAt: Date(),
            isDeleted: false,
            likeCount: 0,
            replyCount: 0,
            isPinned: false,
            pinnedAt: nil,
            pinnedBy: nil,
            parentCommentID: nil,
            attachments: []
        )
    }

    private func makeProfile(nickname: String, avatar: String?) -> UserPublicProfile {
        UserPublicProfile(
            userID: "author-1",
            nickname: nickname,
            avatarThumbPath: avatar,
            avatarOriginalPath: nil,
            createdAt: nil,
            updatedAt: nil
        )
    }
}

private final class CommentAuthorProfileRepositoryFake: UserPublicProfileRepositoryProtocol {
    private var responses: [Result<[String: UserPublicProfile], Error>]
    private(set) var fetchCallCount = 0

    init(responses: [Result<[String: UserPublicProfile], Error>]) {
        self.responses = responses
    }

    func fetchProfile(userID: String) async throws -> UserPublicProfile {
        let profiles = try await fetchProfiles(userIDs: [userID])
        guard let profile = profiles[userID] else { throw TestError.failed }
        return profile
    }

    func fetchProfiles(userIDs: [String]) async throws -> [String: UserPublicProfile] {
        fetchCallCount += 1
        guard responses.isEmpty == false else { return [:] }
        return try responses.removeFirst().get()
    }
}

private struct CommentAuthorCurrentUserIDFake: CurrentUserIDProviding {
    var currentUserID: UserID? { nil }
}

private struct CommentAuthorCurrentUserFake: CurrentUserProviding {
    var email: String { "" }
    var canonicalUserID: String { "" }
    var nickname: String? { nil }
    var avatarPath: String? { nil }
    var profile: UserPublicProfile? { nil }
}

private enum TestError: Error {
    case failed
}
