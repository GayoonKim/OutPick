//
//  PostDetailScreenViewModelTests.swift
//  OutPickTests
//
//  Created by Codex on 5/15/26.
//

import Foundation
import FirebaseFirestore
import Testing
@testable import OutPick

@MainActor
struct PostDetailScreenViewModelTests {
    @Test func hiddenRepresentativeCommentRefreshesNextRepresentativeComment() async throws {
        let brandID = BrandID(value: "brand-1")
        let seasonID = SeasonID(value: "season-1")
        let postID = PostID(value: "post-1")
        let hiddenComment = makeComment(
            id: CommentID(value: "comment-hidden"),
            postID: postID,
            userID: UserID(value: "user-hidden")
        )
        let nextRepresentativeComment = makeComment(
            id: CommentID(value: "comment-next"),
            postID: postID,
            userID: UserID(value: "user-next"),
            likeCount: 5
        )
        let post = makePost(
            id: postID,
            brandID: brandID,
            seasonID: seasonID,
            commentCount: 2
        )
        let loadUseCase = LoadPostDetailUseCaseSpy(contents: [
            PostDetailContent(
                post: post,
                comments: [hiddenComment],
                visibleCommentCount: 2,
                commentErrorMessage: nil
            ),
            PostDetailContent(
                post: post,
                comments: [nextRepresentativeComment],
                visibleCommentCount: 1,
                commentErrorMessage: nil
            )
        ])
        let interactionStore = LookbookInteractionStore(
            maxPostStateCount: 10,
            maxCommentStateCount: 10,
            stateRetentionInterval: 60
        )
        let viewModel = PostDetailScreenViewModel(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            useCase: loadUseCase,
            loadHiddenUserIDsUseCase: EmptyHiddenUserIDsUseCase(),
            postUserStateRepository: EmptyPostUserStateRepository(),
            engagementInteractionUseCase: PostEngagementInteractionUseCase(
                repository: UnusedPostEngagementRepository(),
                postInteractionStore: interactionStore
            ),
            postInteractionStore: interactionStore,
            commentInteractionStore: interactionStore,
            currentUserIDProvider: StaticCurrentUserIDProvider(currentUserID: nil)
        )

        await viewModel.loadIfNeeded()

        #expect(viewModel.comments.map(\.id) == [hiddenComment.id])
        #expect(loadUseCase.executeCallCount == 1)

        interactionStore.hideCommentIDs([hiddenComment.id])

        try await waitUntil {
            viewModel.comments.map(\.id) == [nextRepresentativeComment.id]
        }

        #expect(loadUseCase.executeCallCount == 2)
        #expect(viewModel.comments.map(\.id) == [nextRepresentativeComment.id])
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        _ predicate: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while predicate() == false && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func makePost(
        id: PostID,
        brandID: BrandID,
        seasonID: SeasonID,
        commentCount: Int
    ) -> LookbookPost {
        LookbookPost(
            id: id,
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
                likeCount: 0,
                commentCount: commentCount,
                replacementCount: 0,
                saveCount: 0,
                viewCount: nil
            ),
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func makeComment(
        id: CommentID,
        postID: PostID,
        userID: UserID,
        likeCount: Int = 0
    ) -> OutPick.Comment {
        OutPick.Comment(
            id: id,
            postID: postID,
            userID: userID,
            message: "댓글",
            createdAt: Date(),
            isDeleted: false,
            likeCount: likeCount,
            replyCount: 0,
            isPinned: false,
            pinnedAt: nil,
            pinnedBy: nil,
            parentCommentID: nil,
            attachments: []
        )
    }
}

private final class LoadPostDetailUseCaseSpy: LoadPostDetailUseCaseProtocol {
    private let contents: [PostDetailContent]
    private(set) var executeCallCount = 0

    init(contents: [PostDetailContent]) {
        self.contents = contents
    }

    func execute(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        hiddenUserIDs: Set<UserID>
    ) async throws -> PostDetailContent {
        executeCallCount += 1
        let index = min(executeCallCount - 1, contents.count - 1)
        return contents[index]
    }
}

private struct EmptyHiddenUserIDsUseCase: LoadHiddenCommentUserIDsUseCaseProtocol {
    func execute(currentUserID: UserID) async throws -> Set<UserID> {
        []
    }
}

private struct EmptyPostUserStateRepository: PostUserStateRepositoryProtocol {
    func fetchPostUserState(
        userID: UserID,
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID
    ) async throws -> PostUserState? {
        nil
    }

    func fetchLikedPostUserStates(
        userID: UserID,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> PostUserStatePage {
        PostUserStatePage(items: [], last: nil)
    }
}

private struct UnusedPostEngagementRepository: PostEngagementRepositoryProtocol {
    func setLike(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        isLiked: Bool
    ) async throws -> PostEngagementResult {
        throw UnexpectedRepositoryCallError()
    }

    func setSave(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        isSaved: Bool
    ) async throws -> PostEngagementResult {
        throw UnexpectedRepositoryCallError()
    }
}

private struct StaticCurrentUserIDProvider: CurrentUserIDProviding {
    let currentUserID: UserID?
}

private struct UnexpectedRepositoryCallError: Error {}
