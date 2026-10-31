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
            importRequestStore: UnavailableLookbookImportRequestStore(),
            brandRepository: fixture,
            brandSearchRepository: fixture,
            brandRequestRepository: fixture,
            brandEngagementRepository: fixture,
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
    private actor FirstFailure {
        private var failedPaths: Set<String> = []

        func shouldFail(_ path: String) -> Bool {
            failedPaths.insert(path).inserted
        }
    }

    private let firstFailure = FirstFailure()

    func loadImage(path: String, maxBytes: Int) async throws -> UIImage {
        if ProcessInfo.processInfo.arguments.contains("--uitest-lookbook-image-fail-once"),
           await firstFailure.shouldFail(path) {
            throw URLError(.cannotLoadFromNetwork)
        }
        return UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
            OutPickTheme.ColorToken.surfaceBase.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
    }

    func cachedRemoteImage(request: LookbookHTTPImageRequest) async -> LookbookHTTPImageCache.CachedImage? {
        if ProcessInfo.processInfo.arguments.contains("--uitest-lookbook-image-fail-once") { return nil }
        return await LookbookHTTPImageCache.shared.cachedImage(for: request)
    }

    func updatedRemoteImage(request: LookbookHTTPImageRequest) async throws -> UIImage {
        if ProcessInfo.processInfo.arguments.contains("--uitest-lookbook-image-fail-once") {
            throw URLError(.cannotLoadFromNetwork)
        }
        return try await LookbookHTTPImageCache.shared.updatedImage(for: request)
    }

    func storeImageData(_ data: Data, path: String) async throws {}

    func removeImage(path: String) async {}

    func prefetch(
        items: [(path: String, maxBytes: Int)],
        concurrency: Int,
        storePolicy: ImageCacheStorePolicy
    ) async { }

    func prefetchAssets(items: [LookbookAssetImageRequest], concurrency: Int, storePolicy: ImageCacheStorePolicy) async { }
}

private final class LookbookUITestFixtureStore:
    BrandRepositoryProtocol,
    BrandSearchRepositoryProtocol,
    BrandRequestRepositoryProtocol,
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

    private enum FixtureError: Error {
        case unsupported
    }

    private let now = Date(timeIntervalSince1970: 1_779_100_000)
    private var historyPageFailureEmitted = false

    private var brand: Brand {
        Brand(
            id: LookbookUITestFixtureRepositoryProviderFactory.brandID,
            name: "UI Test Brand",
            englishName: nil,
            websiteURL: nil,
            lookbookArchiveURL: nil,
            logoThumbPath: imageFailureFixtureEnabled ? "uitest-brand-logo" : nil,
            logoDetailPath: nil,
            logoOriginalPath: nil,
            isFeatured: true,
            moodIDs: imageFailureFixtureEnabled ? [] : ["minimal"],
            discoveryStatus: .success,
            lastDiscoveryErrorMessage: nil,
            lastDiscoveryRequestedAt: nil,
            lastDiscoveryCompletedAt: nil,
            metrics: BrandMetrics(likeCount: 0, viewCount: 0, popularScore: 0),
            deletionStatus: .active,
            updatedAt: now,
            publicationStatus: "public"
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
            coverPath: imageFailureFixtureEnabled ? "uitest-season-cover" : nil,
            coverRemoteURL: nil,
            description: "UI 테스트용 시즌",
            tagIDs: [],
            moodIDs: [],
            status: .published,
            deletionStatus: .active,
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
                    thumbPath: imageFailureFixtureEnabled ? "uitest-post-thumbnail" : nil,
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
            deletionStatus: .active,
            createdAt: now,
            updatedAt: now
        )
    }

    private var imageFailureFixtureEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitest-lookbook-image-fail-once")
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

    func fetchInterestedStyleBrands(
        moodIDs: [String],
        limit: Int,
        after cursor: InterestedStyleBrandCursor?
    ) async throws -> InterestedStyleBrandPage {
        if ProcessInfo.processInfo.arguments.contains("--uitest-lookbook-interest-failure") {
            // 재조회 중 오류 카드가 진행 표시로 교체되는지 확인하는 모의 지연이다.
            try await Task.sleep(nanoseconds: 3_000_000_000)
            throw URLError(.cannotLoadFromNetwork)
        }
        if ProcessInfo.processInfo.arguments.contains("--uitest-lookbook-interest-empty") {
            return InterestedStyleBrandPage(items: [], nextCursor: nil)
        }
        let matches = brand.moodIDs.contains { moodIDs.contains($0) }
        return InterestedStyleBrandPage(
            items: matches ? [brand] : [],
            nextCursor: nil
        )
    }

    func searchBrands(query: String, limit: Int) async throws -> [Brand] {
        brand.name.lowercased().contains(query.lowercased()) ? [brand] : []
    }






    func submitBrandRequest(
        brandName: String,
        websiteURL: String,
        englishBrandName: String?
    ) async throws -> BrandRequestSubmissionReceipt {
        let fails = ProcessInfo.processInfo.arguments.contains("--uitest-brand-request-failure")
        if fails || ProcessInfo.processInfo.arguments.contains("--uitest-brand-request-delayed-success") {
            try await Task.sleep(nanoseconds: 3_000_000_000)
        }
        if fails {
            throw CloudFunctionsClientError.missingField("resolvedBrandID")
        }
        return .init(requestID: "fixture-request", groupID: "fixture-group",
              status: brandName == brand.name ? .added : .submitted, isDuplicate: false,
              remainingToday: 4, resolvedBrandID: brandName == brand.name ? brand.id : nil)
    }

    func listMyBrandRequests(
        scope: BrandRequestListScope,
        limit: Int,
        cursor: BrandRequestPage.Cursor?
    ) async throws -> BrandRequestPage {
        let statuses: [BrandRequestStatus] = scope == .active ? [.submitted, .reviewing] : [.added, .rejected]
        let rows = statuses.map { status in
            BrandRequest(id: "fixture-" + status.rawValue, brandName: "UI Test Brand", normalizedBrandName: "ui test brand",
                englishBrandName: nil, normalizedEnglishBrandName: nil, groupID: "fixture-group",
                dedupeKey: nil, dedupeKeySource: nil, status: status,
                resolvedBrandID: status == .added ? brand.id : nil,
                rejectionReason: status == .rejected ? "공식 룩북 확인 필요" : nil,
                createdAt: now, updatedAt: now)
        }
        if ProcessInfo.processInfo.arguments.contains("--uitest-brand-history-page-failure"), scope == .active {
            if cursor == nil {
                return .init(requests: Array(rows.prefix(1)),
                    nextCursor: .init(createdAt: "2026-10-15T00:00:00.000Z", requestID: "consumed-candidate"), scope: scope)
            }
            if !historyPageFailureEmitted {
                historyPageFailureEmitted = true
                throw BrandRequestFailure.queryBudget
            }
            return .init(requests: Array(rows.suffix(1)), nextCursor: nil, scope: scope)
        }
        return .init(requests: rows, nextCursor: nil, scope: scope)
    }















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
        message: String,
        clientRequestID: UUID
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
        message: String,
        clientRequestID: UUID
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

    func fetchBlockedUsers(blockerUserID: UserID) async throws -> [UserBlock] { [] }

    func unblockUser(blockerUserID: UserID, blockedUserID: UserID) async throws {}

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
