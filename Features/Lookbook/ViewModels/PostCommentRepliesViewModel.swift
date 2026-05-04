//
//  PostCommentRepliesViewModel.swift
//  OutPick
//
//  Created by Codex on 5/1/26.
//

import Foundation

@MainActor
final class PostCommentRepliesViewModel: ObservableObject {
    @Published private(set) var replies: [Comment] = []
    @Published private(set) var authorDisplays: [UserID: CommentAuthorDisplay] = [:]
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isLoadingMore: Bool = false
    @Published private(set) var isSubmittingReply: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var submissionErrorMessage: String?
    @Published var draftMessage: String = ""

    @Published private(set) var parentComment: Comment

    private let brandID: BrandID
    private let seasonID: SeasonID
    private let postID: PostID
    private let useCase: any LoadCommentRepliesUseCaseProtocol
    private let createUseCase: any CreateCommentReplyUseCaseProtocol
    private let userProfileRepository: UserProfileRepositoryProtocol
    private let avatarImageManager: ChatAvatarImageManaging
    private let pageSize: Int
    private let avatarPrefetchLimit: Int
    private let avatarThumbnailMaxBytes: Int

    private var nextCursor: PageCursor?
    private var loadedKey: String?
    private var isRequestingPage: Bool = false
    private var prefetchedAvatarPaths: Set<String> = []

    var hasMoreReplies: Bool {
        nextCursor != nil
    }

    var canSubmitReply: Bool {
        draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
            isSubmittingReply == false
    }

    init(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        parentComment: Comment,
        useCase: any LoadCommentRepliesUseCaseProtocol,
        createUseCase: any CreateCommentReplyUseCaseProtocol,
        userProfileRepository: UserProfileRepositoryProtocol = FirebaseRepositoryProvider.shared.userProfileRepository,
        avatarImageManager: ChatAvatarImageManaging = AvatarImageService.shared,
        pageSize: Int = 30,
        avatarPrefetchLimit: Int = 16,
        avatarThumbnailMaxBytes: Int = 3 * 1024 * 1024
    ) {
        self.brandID = brandID
        self.seasonID = seasonID
        self.postID = postID
        self.parentComment = parentComment
        self.useCase = useCase
        self.createUseCase = createUseCase
        self.userProfileRepository = userProfileRepository
        self.avatarImageManager = avatarImageManager
        self.pageSize = pageSize
        self.avatarPrefetchLimit = avatarPrefetchLimit
        self.avatarThumbnailMaxBytes = avatarThumbnailMaxBytes
    }

    func loadIfNeeded() async {
        let key = stateKey()
        guard loadedKey != key else { return }
        await loadPage(reset: true)
    }

    func refresh() async {
        loadedKey = nil
        await loadPage(reset: true)
    }

    func loadNextPage() async {
        guard hasMoreReplies else { return }
        await loadPage(reset: false)
    }

    func displayItem(for comment: Comment) -> CommentDisplayItem {
        CommentDisplayItem(
            comment: comment,
            author: authorDisplays[comment.userID] ?? .unknown(userID: comment.userID)
        )
    }

    func prefetchAuthorAvatars(around commentID: CommentID) {
        let comments = [parentComment] + replies
        guard let index = comments.firstIndex(where: { $0.id == commentID }) else { return }

        let upperBound = min(comments.count, index + avatarPrefetchLimit)
        let paths = comments[index..<upperBound]
            .compactMap { authorDisplays[$0.userID]?.avatarPath }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { prefetchedAvatarPaths.contains($0) == false }

        guard paths.isEmpty == false else { return }
        prefetchedAvatarPaths.formUnion(paths)

        Task {
            await avatarImageManager.prefetchAvatars(
                paths: paths,
                maxBytes: avatarThumbnailMaxBytes,
                maxConcurrent: 4
            )
        }
    }

    @discardableResult
    func submitReply() async -> CommentMutationResult? {
        guard isSubmittingReply == false else { return nil }

        let message = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard message.isEmpty == false else {
            submissionErrorMessage = CommentSubmissionError.emptyMessage.localizedDescription
            return nil
        }

        isSubmittingReply = true
        submissionErrorMessage = nil
        defer {
            isSubmittingReply = false
        }

        do {
            let result = try await createUseCase.execute(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID,
                parentCommentID: parentComment.id,
                message: message
            )
            parentComment.replyCount = result.replyCount
            draftMessage = ""
            loadedKey = nil
            await loadPage(reset: true)
            return result
        } catch {
            submissionErrorMessage = "답글을 등록하지 못했습니다."
            return nil
        }
    }

    private func loadPage(reset: Bool) async {
        guard isRequestingPage == false else { return }
        isRequestingPage = true
        if reset {
            isLoading = true
            errorMessage = nil
        } else {
            isLoadingMore = true
        }
        defer {
            isRequestingPage = false
            isLoading = false
            isLoadingMore = false
        }

        do {
            await loadMissingAuthors(for: [parentComment])
            let page = try await useCase.execute(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID,
                parentCommentID: parentComment.id,
                page: PageRequest(
                    size: pageSize,
                    cursor: reset ? nil : nextCursor
                )
            )

            nextCursor = page.nextCursor
            if reset {
                replies = page.items
                loadedKey = stateKey()
            } else {
                replies.append(contentsOf: page.items)
            }
            await loadMissingAuthors(for: page.items)
        } catch {
            errorMessage = "답글을 불러오지 못했습니다."
        }
    }

    private func loadMissingAuthors(for comments: [Comment]) async {
        let missingUserIDs = Array(
            Set(comments.map(\.userID))
                .filter { authorDisplays[$0] == nil }
        )
        guard missingUserIDs.isEmpty == false else { return }

        let rawUserIDs = missingUserIDs.map(\.value)
        guard let profiles = try? await userProfileRepository.fetchUserProfiles(userIDs: rawUserIDs) else {
            applyUnknownAuthors(for: missingUserIDs)
            return
        }

        var nextAuthorDisplays = authorDisplays
        for userID in missingUserIDs {
            if let profile = profiles[userID.value] {
                nextAuthorDisplays[userID] = CommentAuthorDisplay(
                    userID: userID,
                    nickname: resolvedNickname(from: profile),
                    avatarPath: profile.thumbPath ?? profile.originalPath
                )
            } else {
                nextAuthorDisplays[userID] = .unknown(userID: userID)
            }
        }
        authorDisplays = nextAuthorDisplays
    }

    private func applyUnknownAuthors(for userIDs: [UserID]) {
        var nextAuthorDisplays = authorDisplays
        for userID in userIDs where nextAuthorDisplays[userID] == nil {
            nextAuthorDisplays[userID] = .unknown(userID: userID)
        }
        authorDisplays = nextAuthorDisplays
    }

    private func resolvedNickname(from profile: UserProfile) -> String {
        let nickname = profile.nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let nickname, nickname.isEmpty == false {
            return nickname
        }
        return "알 수 없는 사용자"
    }

    private func stateKey() -> String {
        "\(brandID.value)|\(seasonID.value)|\(postID.value)|\(parentComment.id.value)"
    }
}
