//
//  LookbookUITestFixtureRepositoryProvider.swift
//  OutPick
//
//  Created by Codex on 5/18/26.
//

#if DEBUG
import Foundation
import UIKit
import FirebaseFirestore

enum LookbookUITestFixtureRepositoryProviderFactory {
    static let brandID = BrandID(value: "uitest-brand")
    static let seasonID = SeasonID(value: "uitest-season")
    static let postID = PostID(value: "uitest-post")
    static let rootCommentID = CommentID(value: "uitest-root-comment")
    static let replyID = CommentID(value: "uitest-reply")
    static let currentUserID = UserID(value: "uitest-user")
    static let otherUserID = UserID(value: "uitest-author")

    @MainActor
    static func makeProvider() -> LookbookRepositoryProvider {
        let fixture = LookbookUITestFixtureStore()
        return LookbookRepositoryProvider(
            brandRepository: fixture,
            brandEngagementRepository: fixture,
            brandStore: CloudFunctionsBrandStore(),
            seasonRepository: fixture,
            seasonEngagementRepository: fixture,
            seasonUserStateRepository: fixture,
            postRepository: fixture,
            postEngagementRepository: fixture,
            commentRepository: fixture,
            commentWritingRepository: fixture,
            commentEngagementRepository: fixture,
            commentSafetyRepository: fixture,
            userBlockRepository: fixture,
            postUserStateRepository: fixture,
            brandUserStateRepository: fixture,
            commentUserStateRepository: fixture,
            brandImageCache: LookbookUITestFixtureImageCache()
        )
    }
}

private final class LookbookUITestFixtureImageCache: BrandImageCacheProtocol {
    func loadImage(path: String, maxBytes: Int) async throws -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
            UIColor.systemGray5.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
    }

    func prefetch(
        items: [(path: String, maxBytes: Int)],
        concurrency: Int,
        storePolicy: ImageCacheStorePolicy
    ) async { }
}

private final class LookbookUITestFixtureStore:
    BrandRepositoryProtocol,
    BrandEngagementRepositoryProtocol,
    SeasonRepositoryProtocol,
    SeasonEngagementRepositoryProtocol,
    SeasonUserStateRepositoryProtocol,
    PostRepositoryProtocol,
    PostEngagementRepositoryProtocol,
    CommentRepositoryProtocol,
    CommentWritingRepositoryProtocol,
    CommentEngagementRepositoryProtocol,
    CommentSafetyRepositoryProtocol,
    UserBlockRepositoryProtocol,
    PostUserStateRepositoryProtocol,
    BrandUserStateRepositoryProtocol,
    CommentUserStateRepositoryProtocol {

    private let now = Date(timeIntervalSince1970: 1_779_100_000)

    private var brand: Brand {
        Brand(
            id: LookbookUITestFixtureRepositoryProviderFactory.brandID,
            name: "UI Test Brand",
            websiteURL: nil,
            lookbookArchiveURL: nil,
            logoThumbPath: nil,
            logoDetailPath: nil,
            logoOriginalPath: nil,
            isFeatured: true,
            discoveryStatus: .success,
            lastDiscoveryErrorMessage: nil,
            lastDiscoveryRequestedAt: nil,
            lastDiscoveryCompletedAt: nil,
            metrics: BrandMetrics(likeCount: 0, viewCount: 0, popularScore: 0),
            updatedAt: now
        )
    }

    private var season: Season {
        Season(
            id: LookbookUITestFixtureRepositoryProviderFactory.seasonID,
            brandID: LookbookUITestFixtureRepositoryProviderFactory.brandID,
            displayTitle: "UI Test Season",
            sourceTitle: nil,
            year: 2026,
            term: .ss,
            coverPath: nil,
            coverRemoteURL: nil,
            description: "UI 테스트용 시즌",
            tagIDs: [],
            tagConceptIDs: nil,
            status: .published,
            assetSyncStatus: .ready,
            metadataStatus: .confirmed,
            metadataConfidence: nil,
            sourceURL: nil,
            sourceImportJobID: nil,
            sourceSortIndex: 0,
            postCount: 1,
            likeCount: 0,
            createdAt: now,
            updatedAt: now
        )
    }

    private var post: LookbookPost {
        LookbookPost(
            id: LookbookUITestFixtureRepositoryProviderFactory.postID,
            brandID: LookbookUITestFixtureRepositoryProviderFactory.brandID,
            seasonID: LookbookUITestFixtureRepositoryProviderFactory.seasonID,
            authorID: LookbookUITestFixtureRepositoryProviderFactory.otherUserID,
            media: [
                MediaAsset(
                    type: .image,
                    remoteURL: URL(string: "https://example.com/outpick-uitest-look.jpg")!,
                    thumbPath: nil,
                    detailPath: nil,
                    sourcePageURL: nil
                )
            ],
            caption: "UI 테스트 룩",
            tagIDs: [],
            metrics: PostMetrics(
                likeCount: 3,
                commentCount: 2,
                replacementCount: 0,
                saveCount: 1,
                viewCount: 10
            ),
            createdAt: now,
            updatedAt: now
        )
    }

    private var rootComment: Comment {
        Comment(
            id: LookbookUITestFixtureRepositoryProviderFactory.rootCommentID,
            postID: LookbookUITestFixtureRepositoryProviderFactory.postID,
            userID: LookbookUITestFixtureRepositoryProviderFactory.otherUserID,
            message: "UI 테스트용 루트 댓글",
            createdAt: now,
            isDeleted: false,
            likeCount: 4,
            replyCount: 1,
            isPinned: false,
            pinnedAt: nil,
            pinnedBy: nil,
            parentCommentID: nil,
            attachments: []
        )
    }

    private var ownComment: Comment {
        Comment(
            id: CommentID(value: "uitest-own-comment"),
            postID: LookbookUITestFixtureRepositoryProviderFactory.postID,
            userID: LookbookUITestFixtureRepositoryProviderFactory.currentUserID,
            message: "UI 테스트 사용자가 작성한 댓글",
            createdAt: now.addingTimeInterval(-60),
            isDeleted: false,
            likeCount: 1,
            replyCount: 0,
            isPinned: false,
            pinnedAt: nil,
            pinnedBy: nil,
            parentCommentID: nil,
            attachments: []
        )
    }

    private var reply: Comment {
        Comment(
            id: LookbookUITestFixtureRepositoryProviderFactory.replyID,
            postID: LookbookUITestFixtureRepositoryProviderFactory.postID,
            userID: LookbookUITestFixtureRepositoryProviderFactory.currentUserID,
            message: "UI 테스트용 답글",
            createdAt: now.addingTimeInterval(60),
            isDeleted: false,
            likeCount: 2,
            replyCount: 0,
            isPinned: false,
            pinnedAt: nil,
            pinnedBy: nil,
            parentCommentID: LookbookUITestFixtureRepositoryProviderFactory.rootCommentID,
            attachments: []
        )
    }

    func fetchBrand(brandID: BrandID) async throws -> Brand { brand }

    func fetchBrands(
        sort: BrandSort?,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> BrandPage {
        BrandPage(items: [brand], last: nil)
    }

    func fetchFeaturedBrands(
        sort: BrandSort?,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> BrandPage {
        BrandPage(items: [brand], last: nil)
    }

    func createSeason(
        brandID: BrandID,
        year: Int,
        term: SeasonTerm,
        description: String,
        coverImageData: Data?,
        tagIDs: [TagID],
        tagConceptIDs: [String]?
    ) async throws -> Season { season }

    func fetchSeason(brandID: BrandID, seasonID: SeasonID) async throws -> Season { season }

    func fetchSeasons(
        brandID: BrandID,
        pageSize: Int,
        after last: DocumentSnapshot?
    ) async throws -> SeasonPage {
        SeasonPage(items: [season], last: nil)
    }

    func fetchAllSeasons(brandID: BrandID) async throws -> [Season] { [season] }

    func setLike(
        brandID: BrandID,
        seasonID: SeasonID,
        isLiked: Bool
    ) async throws -> SeasonEngagementResult {
        SeasonEngagementResult(
            brandID: brandID,
            seasonID: seasonID,
            userID: LookbookUITestFixtureRepositoryProviderFactory.currentUserID,
            isLiked: isLiked,
            likeCount: isLiked ? season.likeCount + 1 : season.likeCount
        )
    }

    func fetchSeasonUserState(
        userID: UserID,
        brandID: BrandID,
        seasonID: SeasonID
    ) async throws -> SeasonUserState? {
        SeasonUserState(
            brandID: brandID,
            seasonID: seasonID,
            userID: userID,
            isLiked: true,
            updatedAt: now
        )
    }

    func fetchLikedSeasonUserStates(
        userID: UserID,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> SeasonUserStatePage {
        SeasonUserStatePage(
            items: [
                SeasonUserState(
                    brandID: LookbookUITestFixtureRepositoryProviderFactory.brandID,
                    seasonID: LookbookUITestFixtureRepositoryProviderFactory.seasonID,
                    userID: userID,
                    isLiked: true,
                    updatedAt: now
                )
            ],
            last: nil
        )
    }

    func fetchPosts(
        brandID: BrandID,
        seasonID: SeasonID,
        sort: PostSortOption,
        filterTagIDs: [TagID],
        page: PageRequest
    ) async throws -> PageResponse<LookbookPost> {
        PageResponse(items: [post], nextCursor: nil)
    }

    func fetchPost(brandID: BrandID, seasonID: SeasonID, postID: PostID) async throws -> LookbookPost {
        post
    }

    func fetchPostsByTag(
        tagID: TagID,
        sort: PostSortOption,
        page: PageRequest
    ) async throws -> PageResponse<LookbookPost> {
        PageResponse(items: [post], nextCursor: nil)
    }

    func setLike(
        brandID: BrandID,
        isLiked: Bool
    ) async throws -> BrandEngagementResult {
        BrandEngagementResult(
            brandID: brandID,
            userID: LookbookUITestFixtureRepositoryProviderFactory.currentUserID,
            isLiked: isLiked,
            likeCount: isLiked ? brand.metrics.likeCount + 1 : brand.metrics.likeCount
        )
    }

    func setLike(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        isLiked: Bool
    ) async throws -> PostEngagementResult {
        PostEngagementResult(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            userID: LookbookUITestFixtureRepositoryProviderFactory.currentUserID,
            isLiked: isLiked,
            isSaved: false,
            metrics: post.metrics
        )
    }

    func setSave(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        isSaved: Bool
    ) async throws -> PostEngagementResult {
        PostEngagementResult(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            userID: LookbookUITestFixtureRepositoryProviderFactory.currentUserID,
            isLiked: false,
            isSaved: isSaved,
            metrics: post.metrics
        )
    }

    func fetchRepresentativeComment(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID
    ) async throws -> Comment? {
        rootComment
    }

    func fetchPinnedRootComments(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        limit: Int
    ) async throws -> [Comment] {
        []
    }

    func fetchRootComments(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        sort: CommentSortOption,
        page: PageRequest
    ) async throws -> PageResponse<Comment> {
        PageResponse(items: [rootComment, ownComment], nextCursor: nil)
    }

    func fetchReplies(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        parentCommentID: CommentID,
        page: PageRequest
    ) async throws -> PageResponse<Comment> {
        PageResponse(items: [reply], nextCursor: nil)
    }

    func createComment(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        message: String
    ) async throws -> CommentMutationResult {
        CommentMutationResult(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            commentID: CommentID(value: "uitest-created-comment"),
            userID: LookbookUITestFixtureRepositoryProviderFactory.currentUserID,
            parentCommentID: nil,
            commentCount: 3,
            replyCount: 0
        )
    }

    func createReply(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        parentCommentID: CommentID,
        message: String
    ) async throws -> CommentMutationResult {
        CommentMutationResult(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            commentID: CommentID(value: "uitest-created-reply"),
            userID: LookbookUITestFixtureRepositoryProviderFactory.currentUserID,
            parentCommentID: parentCommentID,
            commentCount: 2,
            replyCount: 2
        )
    }

    func deleteComment(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        commentID: CommentID,
        reason: String?
    ) async throws -> CommentDeletionResult {
        CommentDeletionResult(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            commentID: commentID,
            userID: LookbookUITestFixtureRepositoryProviderFactory.currentUserID,
            parentCommentID: nil,
            targetType: .comment,
            deletedReplyCount: 1,
            deletedCommentCount: 2,
            commentCount: 0,
            replyCount: 0
        )
    }

    func setLike(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        commentID: CommentID,
        isLiked: Bool
    ) async throws -> CommentEngagementResult {
        CommentEngagementResult(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            commentID: commentID,
            userID: LookbookUITestFixtureRepositoryProviderFactory.currentUserID,
            parentCommentID: nil,
            isLiked: isLiked,
            likeCount: isLiked ? 5 : 4
        )
    }

    func reportComment(
        reporterUserID: UserID,
        target: CommentReportTarget,
        reason: CommentReportReason,
        detail: String?
    ) async throws -> CommentReport {
        CommentReport(
            id: CommentReportID(value: "uitest-report"),
            reporterUserID: reporterUserID,
            target: target,
            reason: reason,
            detail: detail,
            status: .pending,
            createdAt: now
        )
    }

    func blockUser(
        blockerUserID: UserID,
        blockedUserID: UserID,
        blockedUserNicknameSnapshot: String?,
        source: UserBlockSource
    ) async throws -> UserBlock {
        UserBlock(
            blockerUserID: blockerUserID,
            blockedUserID: blockedUserID,
            blockedUserNicknameSnapshot: blockedUserNicknameSnapshot,
            source: source,
            createdAt: now
        )
    }

    func fetchBlockedUserIDs(blockerUserID: UserID) async throws -> Set<UserID> { [] }

    func fetchHiddenCommentUserIDs(currentUserID: UserID) async throws -> Set<UserID> { [] }

    func fetchPostUserState(
        userID: UserID,
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID
    ) async throws -> PostUserState? {
        PostUserState(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            userID: userID,
            isLiked: false,
            isSaved: false,
            updatedAt: now
        )
    }

    func fetchLikedPostUserStates(
        userID: UserID,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> PostUserStatePage {
        PostUserStatePage(items: [], last: nil)
    }

    func fetchBrandUserState(
        userID: UserID,
        brandID: BrandID
    ) async throws -> BrandUserState? {
        BrandUserState(brandID: brandID, userID: userID, isLiked: false, updatedAt: now)
    }

    func fetchLikedBrandUserStates(
        userID: UserID,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> BrandUserStatePage {
        BrandUserStatePage(items: [], last: nil)
    }

    func fetchCommentUserStates(
        userID: UserID,
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        commentIDs: [CommentID]
    ) async throws -> [CommentID: CommentUserState] {
        [:]
    }
}
#endif
