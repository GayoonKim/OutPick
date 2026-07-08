//
//  LoadLikedPostsUseCaseTests.swift
//  OutPickTests
//
//  Created by Codex on 6/2/26.
//

import Foundation
import FirebaseFirestore
import Testing
@testable import OutPick

@MainActor
struct LoadLikedPostsUseCaseTests {
    @Test func executeCombinesLikedPostStatesWithPostDocuments() async throws {
        let userID = UserID(value: "user-1")
        let brandID = BrandID(value: "brand-1")
        let seasonID = SeasonID(value: "season-1")
        let post = makePost(brandID: brandID, seasonID: seasonID, postID: PostID(value: "post-1"))
        let state = PostUserState(
            brandID: brandID,
            seasonID: seasonID,
            postID: post.id,
            userID: userID,
            isLiked: true,
            isSaved: false,
            updatedAt: Date(),
            likedAt: Date()
        )
        let stateRepository = PostUserStateRepositoryFake(states: [state])
        let postRepository = PostRepositoryFake(posts: [post.id: post])
        let useCase = LoadLikedPostsUseCase(
            postUserStateRepository: stateRepository,
            postRepository: postRepository
        )

        let page = try await useCase.execute(userID: userID, limit: 20, after: nil)

        #expect(page.items.map(\.id) == ["\(brandID.value)_\(seasonID.value)_\(post.id.value)"])
        #expect(page.items.first?.userState == state)
        #expect(stateRepository.requests.map(\.userID) == [userID])
        #expect(postRepository.fetchRequests.count == 1)
        #expect(postRepository.fetchRequests.first?.brandID == brandID)
        #expect(postRepository.fetchRequests.first?.seasonID == seasonID)
        #expect(postRepository.fetchRequests.first?.postID == post.id)
    }

    @Test func executeSkipsMissingPostDocuments() async throws {
        let userID = UserID(value: "user-1")
        let state = PostUserState(
            brandID: BrandID(value: "brand-1"),
            seasonID: SeasonID(value: "season-1"),
            postID: PostID(value: "post-missing"),
            userID: userID,
            isLiked: true,
            isSaved: false,
            updatedAt: Date(),
            likedAt: Date()
        )
        let useCase = LoadLikedPostsUseCase(
            postUserStateRepository: PostUserStateRepositoryFake(states: [state]),
            postRepository: PostRepositoryFake(posts: [:])
        )

        let page = try await useCase.execute(userID: userID, limit: 20, after: nil)

        #expect(page.items.isEmpty)
    }

    private func makePost(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID
    ) -> LookbookPost {
        LookbookPost(
            id: postID,
            brandID: brandID,
            seasonID: seasonID,
            authorID: UserID(value: "author-1"),
            media: [
                MediaAsset(
                    type: .image,
                    remoteURL: URL(string: "https://example.com/post.jpg")!,
                    thumbPath: nil,
                    detailPath: nil,
                    sourcePageURL: nil
                )
            ],
            caption: nil,
            tagIDs: [],
            metrics: PostMetrics(
                likeCount: 3,
                commentCount: 2,
                replacementCount: 0,
                saveCount: 0,
                viewCount: nil
            ),
            deletionStatus: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

@MainActor
private final class PostUserStateRepositoryFake: PostUserStateRepositoryProtocol {
    struct Request: Equatable {
        let userID: UserID
        let limit: Int
    }

    private let states: [PostUserState]
    private(set) var requests: [Request] = []

    init(states: [PostUserState]) {
        self.states = states
    }

    func fetchPostUserState(
        userID: UserID,
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID
    ) async throws -> PostUserState? {
        states.first {
            $0.userID == userID &&
                $0.brandID == brandID &&
                $0.seasonID == seasonID &&
                $0.postID == postID
        }
    }

    func fetchLikedPostUserStates(
        userID: UserID,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> PostUserStatePage {
        requests.append(Request(userID: userID, limit: limit))
        return PostUserStatePage(items: states, last: nil)
    }
}

@MainActor
private final class PostRepositoryFake: PostRepositoryProtocol {
    private let posts: [PostID: LookbookPost]
    private(set) var fetchRequests: [(brandID: BrandID, seasonID: SeasonID, postID: PostID)] = []

    init(posts: [PostID: LookbookPost]) {
        self.posts = posts
    }

    func fetchPosts(
        brandID: BrandID,
        seasonID: SeasonID,
        sort: PostSortOption,
        filterTagIDs: [TagID],
        page: PageRequest
    ) async throws -> PageResponse<LookbookPost> {
        PageResponse(items: Array(posts.values), nextCursor: nil)
    }

    func fetchPost(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID
    ) async throws -> LookbookPost {
        fetchRequests.append((brandID: brandID, seasonID: seasonID, postID: postID))
        guard let post = posts[postID] else {
            throw NSError(domain: "PostRepositoryFake", code: -1)
        }
        return post
    }

    func fetchPostsByTag(
        tagID: TagID,
        sort: PostSortOption,
        page: PageRequest
    ) async throws -> PageResponse<LookbookPost> {
        PageResponse(items: Array(posts.values), nextCursor: nil)
    }
}
